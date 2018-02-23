DROP TABLE [Pbsa].[dbo].Debit_Transactions;

CREATE TABLE [Pbsa].dbo.Debit_Transactions (
      [Transaction Date] NVARCHAR(255),
      [Terminal Identifier] NVARCHAR(255),
      [Terminal Country] NVARCHAR(255),
      [Transaction Type] NVARCHAR(255),
      [Transaction Amount] NVARCHAR(255),
      [Transaction Time] NVARCHAR(255),
      [Transaction Status] NVARCHAR(255),
      [From Account Number]   NVARCHAR(255)
      );

BULK INSERT Debit_Transactions 
-- FROM 'D:\Prime\Import\WKDIR\BKCN_--_All_PIN_Based_Transactions_Based_on_Terminal.csv'
FROM 'E:\Tactical\BKCN_--_All_PIN_Based_Transactions_Based_on_Terminal.csv'
with
(FieldTerminator = '\t',
RowTerminator = '\n',
FIRSTROW = 2
)



Update Debit_Transactions
Set [Transaction Date] = Coalesce(REPLACE([Transaction Date], '"', ''), '')
Alter Table Debit_Transactions Alter Column [Transaction Date] Datetime

Update Debit_Transactions
Set [Terminal Identifier] = LTRIM(RTRIM(Coalesce(REPLACE([Terminal Identifier], '"', ''), '')))

Update Debit_Transactions
Set [Terminal Country] = LTRIM(RTRIM(Coalesce(REPLACE([Terminal Country], '"', ''), '')))

Update Debit_Transactions
Set [Transaction Type] = LTRIM(RTRIM(Coalesce(REPLACE([Transaction Type], '"', ''), '')))

Update Debit_Transactions
Set [Transaction Amount] = LTRIM(RTRIM(Coalesce(REPLACE([Transaction Amount], '"', ''), '')))

Update Debit_Transactions
set [Transaction Amount] =  case when isNumeric([Transaction Amount])=1 then cast([Transaction Amount] as FLOAT) else NULL end

 
Update Debit_Transactions
Set [Transaction Time] = LTRIM(RTRIM(Coalesce(REPLACE([Transaction Time], '"', ''), '')))


Update Debit_Transactions
Set [Transaction Status] = LTRIM(RTRIM(Coalesce(REPLACE([Transaction Status], '"', ''), '')))

Update Debit_Transactions
Set [From Account Number] = LTRIM(RTRIM(COALESCE(REPLACE([From Account Number], '"', ''), '')))

Update Debit_Transactions
set [From Account Number] =  case when isNumeric([From Account Number])=1 then cast([From Account Number] as INT) else NULL end

Go

