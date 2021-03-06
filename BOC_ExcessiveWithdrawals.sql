USE [Pbsa]
GO
/****** Object:  StoredProcedure [dbo].[BOC_ExcessiveWithdrawals]    Script Date: 12/18/2016 09:40:07 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ===================================================================================================================================================
-- Description:	Pattern of Excessive ATM Withdrawals 
--				This scenario generates alerts for US accounts with a sudden increase in debit card activity
-- ===================================================================================================================================================

CREATE PROCEDURE [dbo].[BOC_ExcessiveWithdrawals]
	-- Default values have been added for each parameter
	@YearStart			DATETIME		,	-- Start date of 1 year lookback period from for Historical Average calculation
	@YearEnd			DATETIME		,	-- End date of 1 year lookback period from for Historical Average calculation
	@TxnDateStart		DATETIME		,	-- Start date of transactions to be considered for current alert month
	@TxnDateEnd			DATETIME		,	-- End date of transactions to be considered for the current alert month
	@MinSingleDayWD		DECIMAL(19,2)	,	-- Threshold for Minimum Single Day Withdrawal Amount	
	@MinThreeDayAvg		DECIMAL(19,2)	,   -- Threshold for Minimum Three Day Average Withdrawal Amount
	@MinDifference		DECIMAL(6,4)	,	-- Threshold for Minimum % Difference between Three Day and Historical Average
	@MinTxnCnt			INT					-- Threshold for Minimum Transaction Count
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from interfering with SELECT statements
	SET NOCOUNT ON;
	
	-- Clear tables if already present in order to load new data
	
CREATE TABLE #ExcessiveWithdrawals_Tran (
	ID					INT IDENTITY(1,1),  
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

CREATE TABLE #ExcessiveWithdrawals_HistTran (
	ID					INT IDENTITY(1,1),  
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
	
CREATE TABLE #ExcessiveWithdrawals_HistAvg (   
	FromAccountNumber	INT,
	HistAvg				DECIMAL(19,2) );	
	
CREATE TABLE #ExcessiveWithdrawals_TxnCnt (   
	FromAccountNumber	INT,
	TransactionCount	INT );	

CREATE TABLE #ExcessiveWithdrawals_SingleDayWD (   
	FromAccountNumber	INT,
	TransactionDate		DATETIME,
	SingleDayWD			DECIMAL(19,2) );	

CREATE TABLE #ExcessiveWithdrawals_ThreeDayAvg (   
	FromAccountNumber	INT,
	TransactionDate		DATETIME,
	ThreeDayAvg			DECIMAL(19,2) );	

CREATE TABLE #ExcessiveWithdrawals_Max (   
	FromAccountNumber	INT,
	MaxThreeDayAvg		DECIMAL(19,2),
	MaxSingleDayWD		DECIMAL(19,2) );	

CREATE TABLE #ExcessiveWithdrawals_Acct(   
	FromAccountNumber	INT,
	CustomerID			VARCHAR(35),
	CustomerName		VARCHAR(40),
	Relationship		VARCHAR(11),
	CustomerResidence	VARCHAR(11),
	MaxThreeDayAvg		DECIMAL(19,2),
	HistAvg				DECIMAL(19,2),
	Difference			DECIMAL(6,4),
	MaxSingleDayWD		DECIMAL(19,2),
	TransactionCount	INT,
	AlertFlag			INT );	

--DELETE THE TABLE IF IT ALREADY EXIXTS. THIS TABLE HOLDS THE ALERTS GENERATED FROM PRIOR RUN
	  IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'ExcessiveWithdrawals_Alert')
                  BEGIN
                  DROP TABLE ExcessiveWithdrawals_Alert 
            END

      IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'ExcessiveWithdrawals_AlertedTxn')
                  BEGIN
                  DROP TABLE ExcessiveWithdrawals_AlertedTxn
            END

      IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'ExcessiveWithdrawals_Alert1YearTxn')
      
                  BEGIN
                  DROP TABLE ExcessiveWithdrawals_Alert1YearTxn
            END

CREATE TABLE dbo.ExcessiveWithdrawals_Alert (   
	FromAccountNumber	INT,
	CustomerID			VARCHAR(35),
	CustomerName		VARCHAR(40),
	Relationship		VARCHAR(11),
	CustomerResidence	VARCHAR(11),
	MaxThreeDayAvg		DECIMAL(19,2),
	HistAvg				DECIMAL(19,2),
	Difference			DECIMAL(6,4),
	MaxSingleDayWD		DECIMAL(19,2),
	TransactionCount	INT,
	AlertFlag			INT,
	AlertMonth			VARCHAR(20),
	RunDate				DATETIME );	

CREATE TABLE #ExcessiveWithdrawals_AlertedTxn1 (
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
	CustomerResidence	VARCHAR(11) );	
				
CREATE TABLE dbo.ExcessiveWithdrawals_AlertedTxn (
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
	AlertedTxn			INT );		
	
CREATE TABLE dbo.ExcessiveWithdrawals_Alert1YearTxn (
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
	AlertedTxn			INT );		
		
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_Tran Table
-- This temporary table includes all authorized and completed ATM cash withdrawal transactions for US accounts for the current alert month 
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_Tran
(TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence)
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
	WHERE a.[Transaction Date] BETWEEN @TxnDateStart AND @TxnDateEnd 
	AND UPPER(a.[Transaction Type]) = 'CASH WITHDRAWAL'
	AND UPPER(a.[Transaction Status]) = 'AUTHORIZED AND COMPLETED'
	AND UPPER(c.CountryofResidence) = 'US'

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_HistTran Table
-- This temporary table includes all authorized and completed ATM cash withdrawal transactions for US accounts for the historical lookback period of 1 year 
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_HistTran
(TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence)
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
	WHERE a.[Transaction Date] BETWEEN @YearStart AND @YearEnd 
	AND UPPER(a.[Transaction Type]) = 'CASH WITHDRAWAL'
	AND UPPER(a.[Transaction Status]) = 'AUTHORIZED AND COMPLETED'
	AND UPPER(c.CountryofResidence) = 'US'

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_HistAvg Table
-- This temporary table calculates the Historical Daily Average ATM Withdrawal Transaction Amount for each account
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_HistAvg
(FromAccountNumber, HistAvg)
	SELECT FromAccountNumber,	
		   SUM(TransactionAmount)/COUNT(DISTINCT(TransactionDate)) AS HistAvg
	FROM #ExcessiveWithdrawals_HistTran
	GROUP BY FromAccountNumber

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_TxnCnt Table
-- This temporary table calculates the number of transactions for each account during the alert month
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_TxnCnt
(FromAccountNumber, TransactionCount)
	SELECT FromAccountNumber,
		   COUNT(*)
	FROM #ExcessiveWithdrawals_Tran
	GROUP BY FromAccountNumber

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_SingleDayWD Table
-- This temporary table calculates the Single Day ATM Withdrawal Transaction Amount for each account and Transaction Date for the alert month
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_SingleDayWD
(FromAccountNumber, TransactionDate, SingleDayWD)
	SELECT FromAccountNumber,
		   TransactionDate,
		   SUM(TransactionAmount)
	FROM #ExcessiveWithdrawals_Tran
	GROUP BY FromAccountNumber, TransactionDate

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_ThreeDayAvg Table
-- This temporary table calculates the rolling Three Day Average ATM Withdrawal Transaction Amount for each account and Transaction Date for the alert month
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_ThreeDayAvg
(FromAccountNumber, TransactionDate, ThreeDayAvg)
	SELECT a.FromAccountNumber, 
	       a.TransactionDate,
	       AVG(b.SingleDayWD)
	FROM #ExcessiveWithdrawals_SingleDayWD a  -- Use daily aggregated transaction data
	LEFT JOIN #ExcessiveWithdrawals_SingleDayWD b 
	ON a.FromAccountNumber = b.FromAccountNumber
	AND b.TransactionDate BETWEEN DATEADD(DAY, -2, a.TransactionDate) AND a.TransactionDate
	GROUP BY a.FromAccountNumber, a.TransactionDate
		 
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_Max Table
-- This temporary table calculates the maximum Three Day Average and Single Day Transaction Amount for each account for the alert month
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_Max
(FromAccountNumber, MaxThreeDayAvg, MaxSingleDayWD)
	SELECT a.FromAccountNumber,
		   MAX(a.ThreeDayAvg),
		   MAX(b.SingleDayWD)
	FROM #ExcessiveWithdrawals_ThreeDayAvg a
	LEFT JOIN #ExcessiveWithdrawals_SingleDayWD b ON a.FromAccountNumber = b.FromAccountNumber
	GROUP BY a.FromAccountNumber

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_Acct Table
-- This table uses an alert flag indicator for each account to demonstrate whether or not the account has passed the alerting threshold requirements
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_Acct
(FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, MaxThreeDayAvg, HistAvg, Difference, MaxSingleDayWD, TransactionCount, AlertFlag)
	SELECT a.FromAccountNumber,
		   d.CustomerID,
		   d.CustomerName,
		   d.Relationship,
		   d.CustomerResidence,
		   a.MaxThreeDayAvg,
		   b.HistAvg,
		   (a.MaxThreeDayAvg - b.HistAvg)/(NULLIF(b.HistAvg,0)),
		   a.MaxSingleDayWD,
		   c.TransactionCount,
		   CASE WHEN (a.MaxThreeDayAvg - b.HistAvg)/(NULLIF(b.HistAvg,0)) >= @MinDifference
				AND (a.MaxThreeDayAvg >= @MinThreeDayAvg OR a.MaxSingleDayWD >= @MinSingleDayWD)
				AND (c.TransactionCount >= @MinTxnCnt)
				THEN 1 ELSE 0 END AS AlertFlag
	FROM #ExcessiveWithdrawals_Max a
	LEFT JOIN #ExcessiveWithdrawals_HistAvg b ON a.FromAccountNumber = b.FromAccountNumber
	LEFT JOIN #ExcessiveWithdrawals_TxnCnt c ON a.FromAccountNumber = c.FromAccountNumber
	LEFT JOIN (SELECT DISTINCT FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence
		       FROM #ExcessiveWithdrawals_Tran) d ON a.FromAccountNumber = d.FromAccountNumber 

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- ExcessiveWithdrawals_Alert Table
-- This table displays account data and calculations for alerted accounts
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO dbo.ExcessiveWithdrawals_Alert
(FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, MaxThreeDayAvg, HistAvg, Difference, MaxSingleDayWD, TransactionCount, AlertFlag, AlertMonth,
RunDate)
	SELECT *,
		   DATENAME(MONTH, @TxnDateStart) + ' ' + DATENAME(YEAR, @TxnDateStart),
		   GETDATE()
	FROM #ExcessiveWithdrawals_Acct WHERE AlertFlag = 1

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- #ExcessiveWithdrawals_AlertedTxn1 Table
-- This temporary table displays transactions that triggered alerts for all alerted accounts in the current alert month 
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO #ExcessiveWithdrawals_AlertedTxn1
(ID, TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence)
	SELECT DISTINCT ID, a.TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, a.FromAccountNumber, CustomerID, CustomerName,
		   Relationship, CustomerResidence
	FROM #ExcessiveWithdrawals_Tran a
	LEFT JOIN #ExcessiveWithdrawals_HistAvg b 
	ON a.FromAccountNumber = b.FromAccountNumber
	LEFT JOIN #ExcessiveWithdrawals_ThreeDayAvg c 
	ON a.FromAccountNumber = c.FromAccountNumber AND c.TransactionDate BETWEEN a.TransactionDate AND DATEADD(DAY, 2, a.TransactionDate)
	LEFT JOIN #ExcessiveWithdrawals_SingleDayWD d 
	ON a.FromAccountNumber = d.FromAccountNumber AND a.TransactionDate = d.TransactionDate
	LEFT JOIN #ExcessiveWithdrawals_TxnCnt e
	ON a.FromAccountNumber = e.FromAccountNumber
	WHERE (c.ThreeDayAvg - b.HistAvg)/(NULLIF(b.HistAvg,0)) >= @MinDifference 
		  AND (c.ThreeDayAvg >= @MinThreeDayAvg OR d.SingleDayWD >= @MinSingleDayWD)
		  AND (e.TransactionCount >= @MinTxnCnt)
	ORDER BY FromAccountNumber, TransactionDate

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- ExcessiveWithdrawals_AlertedTxn Table
-- This table displays all transactions for all alerted accounts in the current alert month 
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO dbo.ExcessiveWithdrawals_AlertedTxn
(ID, TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, AlertedTxn)
	SELECT DISTINCT ID, TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName,
		   Relationship, CustomerResidence, 
		   CASE WHEN ID IN (SELECT ID FROM #ExcessiveWithdrawals_AlertedTxn1) THEN 1 ELSE 0 END AS AlertedTxn
	FROM #ExcessiveWithdrawals_Tran WHERE FromAccountNumber IN (SELECT FromAccountNumber FROM dbo.ExcessiveWithdrawals_Alert)

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- ExcessiveWithdrawals_Alert1YearTxn Table
-- This table displays all transactions for all alerted accounts in the current alert month as well as the historical lookback period
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO dbo.ExcessiveWithdrawals_Alert1YearTxn
(TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, AlertedTxn)
	SELECT *
	FROM
		(SELECT TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence,
				CASE WHEN ID IN (SELECT ID FROM #ExcessiveWithdrawals_AlertedTxn1) THEN 1 ELSE 0 END AS AlertedTxn
		FROM #ExcessiveWithdrawals_Tran WHERE FromAccountNumber IN (SELECT FromAccountNumber FROM ExcessiveWithdrawals_Alert WHERE AlertFlag = 1)
		UNION ALL
		SELECT TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence,
			   0
		FROM #ExcessiveWithdrawals_HistTran WHERE FromAccountNumber IN (SELECT FromAccountNumber FROM ExcessiveWithdrawals_Alert WHERE AlertFlag = 1)) a
	ORDER BY FromAccountNumber, TransactionDate	

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- DebitCard_AlertArchive Table
-- This table stores alert data for every month that the Debit Card scenarios (Pattern of Excessive Withdrawals and Foreign Debit Card) are run
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO dbo.DebitCard_AlertArchive
	SELECT FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, 'Pattern of Excessive Withdrawals', AlertFlag, AlertMonth, RunDate
	FROM dbo.ExcessiveWithdrawals_Alert

--------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- DebitCard_TranArchive Table
-- This table stores historical transaction data for every month that the Debit Card scenarios (Pattern of Excessive Withdrawals and Foreign Debit Card) are run
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO dbo.DebitCard_TranArchive
	SELECT TransactionDate, TerminalCountry, TransactionType, TransactionAmount, TransactionStatus, FromAccountNumber, CustomerID, CustomerName, Relationship, CustomerResidence, AlertedTxn
	FROM dbo.ExcessiveWithdrawals_Alert1YearTxn
	WHERE TransactionDate NOT IN (SELECT TransactionDate FROM dbo.DebitCard_TranArchive)
	OR FromAccountNumber NOT IN (SELECT FromAccountNumber FROM dbo.DebitCard_TranArchive)
	
END