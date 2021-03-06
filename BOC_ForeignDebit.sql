USE [Pbsa]
GO
/****** Object:  StoredProcedure [dbo].[BOC_ForeignDebit]    Script Date: 12/18/2016 09:40:37 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ===================================================================================================================================================
-- Description:	Foreign Debit Card Transactions 
--				This scenario generates alerts for US accounts with a change in foreign debit card activity
-- ===================================================================================================================================================

CREATE PROCEDURE [dbo].[BOC_ForeignDebit]
	-- Default values have been added for each parameter
	@TxnDateStart		DATETIME		,	 -- Start date of transactions to be considered
	@TxnDateEnd			DATETIME		,	 -- End date of transactions to be considered
	@MinForeignTxn		INT				,	 -- Threshold for Minimum Number of Foreign ATM Withdrawals 
	@MinForeignCtry		INT				     -- Threshold for Minimum Number of Distinct Foreign Countries of ATM Withdrawals 

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from interfering with SELECT statements
	SET NOCOUNT ON;
	
CREATE TABLE #ForeignDebit_Tran (
	ID					INT IDENTITY (1,1),
	TransactionDate		DATETIME,
	TerminalCountry		VARCHAR(35),
	TransactionType		VARCHAR(40),
	TransactionAmount	DECIMAL(19,2),
	TransactionStatus	VARCHAR(40),
	FromAccountNumber	INT,
	CustomerID			VARCHAR(35),
	CustomerName		VARCHAR(40),
	Relationship		VARCHAR(11),
	CustomerResidence	VARCHAR(11) );

CREATE TABLE #ForeignDebit_ForeignTran (
	ID					INT,
	TransactionDate		DATETIME,
	TerminalCountry		VARCHAR(35),
	TransactionType		VARCHAR(40),
	TransactionAmount	DECIMAL(19,2),
	TransactionStatus	VARCHAR(40),
	FromAccountNumber	INT,
	CustomerID			VARCHAR(35),
	CustomerName		VARCHAR(40),
	Relationship		VARCHAR(11),
	CustomerResidence	VARCHAR(11),
	ForeignCountry		INT	);
	
CREATE TABLE #ForeignDebit_Acct (   
	FromAccountNumber	INT,
	ForeignTxn			INT,
	ForeignCtry			INT	);	

CREATE TABLE #ForeignDebit_Acct2 (   
	FromAccountNumber	INT,
	CustomerID			VARCHAR(35),
	CustomerName		VARCHAR(40),
	Relationship		VARCHAR(11),
	CustomerResidence	VARCHAR(11),
	ForeignTxn			INT,
	ForeignCtry			INT,
	AlertFlag			INT	);	

--DELETE THE TABLE IF IT ALREADY EXIXTS. THIS TABLE HOLDS THE ALERTS GENERATED FROM PRIOR RUN
	  IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'ForeignDebit_Alert')
                  BEGIN
                  DROP TABLE ForeignDebit_Alert 
            END

      IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'ForeignDebit_AlertedTxn')
                  BEGIN
                  DROP TABLE ForeignDebit_AlertedTxn
            END

      IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'ForeignDebit_Alert1YearTxn')
      
                  BEGIN
                  DROP TABLE ForeignDebit_Alert1YearTxn
            END

CREATE TABLE [dbo].ForeignDebit_Alert (   
	FromAccountNumber	INT,
	CustomerID			VARCHAR(35),
	CustomerName		VARCHAR(40),
	Relationship		VARCHAR(11),
	CustomerResidence	VARCHAR(11),
	ForeignTxn			INT,
	ForeignCtry			INT,
	AlertFlag			INT,
	AlertMonth			VARCHAR(20),
	RunDate				DATETIME );	

CREATE TABLE [dbo].ForeignDebit_AlertedTxn (
	TransactionDate		DATETIME,
	TerminalCountry		VARCHAR(35),
	TransactionType		VARCHAR(40),
	TransactionAmount	DECIMAL(19,2),
	TransactionStatus	VARCHAR(40),
	FromAccountNumber	INT,
	CustomerID			VARCHAR(35),
	CustomerName		VARCHAR(40),
	Relationship		VARCHAR(11),
	CustomerResidence	VARCHAR(11),
	AlertedTxn			INT );

CREATE TABLE [dbo].ForeignDebit_Alert1YearTxn (
	TransactionDate		DATETIME,
	TerminalCountry		VARCHAR(35),
	TransactionType		VARCHAR(40),
	TransactionAmount	DECIMAL(19,2),
	TransactionStatus	VARCHAR(40),
	FromAccountNumber	INT,
	CustomerID			VARCHAR(35),
	CustomerName		VARCHAR(40),
	Relationship		VARCHAR(11),
	CustomerResidence	VARCHAR(11),
	AlertedTxn			INT );
		
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ForeignDebit_Tran Table
-- This temporary table includes all authorized and completed ATM cash withdrawal transactions for US accounts for the current alert month
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ForeignDebit_Tran
(TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, 
CustomerResidence)
	SELECT a.[Transaction Date],
		   a.[Terminal Country],
		   a.[Transaction Type],
		   a.[Transaction Amount],
		   a.[Transaction Status],
		   ('0'+a.[From Account Number]), -- Adding a 0 in front of Account Number to standardize with the Account Numbers in the Account table
		   b.Cust,
		   c.Name,
		   b.Relationship,
		   c.CountryofResidence
	FROM Debit_Transactions a
	LEFT JOIN (SELECT * FROM AccountOwner WHERE Relationship = '11') b ON ('0'+a.[From Account Number]) = b.Account -- Only use Customer ID of Account Owner
	LEFT JOIN Customer c ON b.Cust = c.ID
	WHERE [Transaction Date] BETWEEN @TxnDateStart AND @TxnDateEnd 
	AND UPPER(a.[Transaction Type]) = 'CASH WITHDRAWAL'
	AND UPPER(a.[Transaction Status]) = 'AUTHORIZED AND COMPLETED'
	AND UPPER(c.CountryofResidence) = 'US'
	
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ForeignDebit_ForeignTran Table
-- This temporary table includes all authorized and completed ATM cash withdrawal transactions for US accounts for the current alert month, including a
--		ForeignCountry flag indicating whether or not the transaction has been conducted in a foreign country (excluding China)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ForeignDebit_ForeignTran
(ID, TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, 
CustomerResidence, ForeignCountry)
	SELECT *,
		   CASE WHEN UPPER(TerminalCountry) NOT IN ('UNITED STATES','CHINA') THEN 1 ELSE 0 END AS ForeignCountry
	FROM #ForeignDebit_Tran

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ForeignDebit_Acct Table
-- This temporary table includes the number of Foreign Transactions and Distinct Foreign Countries for each account for the alert month
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ForeignDebit_Acct
(FromAccountNumber, ForeignTxn, ForeignCtry)
	SELECT FromAccountNumber,
	       COUNT(*) AS ForeignTxn,
	       COUNT(DISTINCT(UPPER(TerminalCountry))) AS ForeignCtry
	FROM #ForeignDebit_ForeignTran
	WHERE ForeignCountry = 1
	GROUP BY FromAccountNumber

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ForeignDebit_Acct2 Table
-- This temporary table includes an alert flag indicator for each account to demonstrate whether or not the account has passed the alerting threshold requirements
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ForeignDebit_Acct2 
(FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, ForeignTxn, ForeignCtry, AlertFlag)
	SELECT a.FromAccountNumber,
		   b.CustomerID,
		   b.CustomerName,
		   b.Relationship,
		   b.CustomerResidence,
		   a.ForeignTxn,
		   a.ForeignCtry,
		   CASE WHEN (a.ForeignTxn >= @MinForeignTxn) OR (a.ForeignCtry >= @MinForeignCtry) THEN 1 ELSE 0 END AS AlertFlag
	FROM #ForeignDebit_Acct a
	LEFT JOIN (SELECT DISTINCT FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence FROM #ForeignDebit_Tran) b
	ON a.FromAccountNumber = b.FromAccountNumber

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- ForeignDebit_Alert Table
-- This table includes an alert flag indicator for each account to demonstrate whether or not the account has passed the alerting threshold requirements
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO [dbo].ForeignDebit_Alert 
(FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, ForeignTxn, ForeignCtry, AlertFlag, AlertMonth, RunDate)
	SELECT *,
		   DATENAME(MONTH, @TxnDateStart) + ' ' + DATENAME(YEAR, @TxnDateStart),
		   GETDATE()
	FROM #ForeignDebit_Acct2 
	WHERE AlertFlag = 1 

---------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- ForeignDebit_AlertedTxn Table
-- This table displays transactions that triggered alerts for all alerted accounts in the current alert month 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO [dbo].ForeignDebit_AlertedTxn
(TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, AlertedTxn)
	SELECT TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, 
		   CASE WHEN ForeignCountry = 1 THEN 1 ELSE 0 END AS AlertedTxn
	FROM #ForeignDebit_ForeignTran 
	WHERE FromAccountNumber IN (SELECT FromAccountNumber FROM [dbo].ForeignDebit_Alert)	 
	ORDER BY FromAccountNumber, TransactionDate 

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- ForeignDebit_Alert1YearTxn Table
-- This table displays all transactions for all alerted accounts in the current alert month as well as the the past year
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO [dbo].ForeignDebit_Alert1YearTxn
(TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, AlertedTxn)
	SELECT a.[Transaction Date],
		   a.[Terminal Country],
		   a.[Transaction Type],
		   a.[Transaction Amount],
		   a.[Transaction Status],
		   ('0'+a.[From Account Number]), -- Adding a 0 in front of Account Number to standardize with the Account Numbers in the Account table
		   b.Cust,
		   c.Name,
		   b.Relationship,
		   c.CountryofResidence,
		   CASE WHEN a.[Transaction Date] BETWEEN @TxnDateStart AND @TxnDateEnd
				AND UPPER(a.[Terminal Country]) NOT IN ('UNITED STATES','CHINA') THEN 1 ELSE 0 END AS AlertedTxn
	FROM Debit_Transactions a
	LEFT JOIN (SELECT * FROM AccountOwner WHERE Relationship = '11') b ON ('0'+a.[From Account Number]) = b.Account -- Only use Customer ID of Account Owner
	LEFT JOIN Customer c ON b.Cust = c.ID
	WHERE [Transaction Date] BETWEEN DATEADD(YEAR, -1, DATEADD(DAY, 1, @TxnDateEnd))  AND @TxnDateEnd 
	AND UPPER(a.[Transaction Type]) = 'CASH WITHDRAWAL'
	AND UPPER(a.[Transaction Status]) = 'AUTHORIZED AND COMPLETED'
	AND UPPER(c.CountryofResidence) = 'US'
	AND ('0'+[From Account Number]) IN (SELECT FromAccountNumber FROM [dbo].ForeignDebit_Alert)	
	ORDER BY ('0'+[From Account Number]), [Transaction Date]	

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- DebitCard_AlertArchive Table
-- This table stores alert data for every month that the Debit Card scenarios (Pattern of Excessive Withdrawals and Foreign Debit Card) are run
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO dbo.DebitCard_AlertArchive
	SELECT FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, 'Foreign Debit Card', AlertFlag, AlertMonth, RunDate 
	FROM dbo.ForeignDebit_Alert

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- DebitCard_TranArchive Table
-- This table stores historical transaction data for every month that the Debit Card scenarios (Pattern of Excessive Withdrawals and Foreign Debit Card) are run
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO dbo.DebitCard_TranArchive
	SELECT TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, AlertedTxn
	FROM [dbo].ForeignDebit_Alert1YearTxn
	WHERE TransactionDate NOT IN (SELECT TransactionDate FROM dbo.DebitCard_TranArchive)
	OR FromAccountNumber NOT IN (SELECT FromAccountNumber FROM dbo.DebitCard_TranArchive)
	
END
