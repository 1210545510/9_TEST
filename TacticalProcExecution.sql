USE [PBSA]
GO
/****** OBJECT:  STOREDPROCEDURE [DBO].[SP_CAROUSEL_TRANSACTIONS]   SCRIPT DATE: 08/16/2016 11:54:17 ******/
SET ANSI_NULLS ON
GO 
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- AUTHOR:		DANESHWARI
-- CREATE DATE: 08/19/16
-- DESCRIPTION:	CAROUSEL TRANSACTIONS
--				THIS SCENARIO MONITORS FOR THE REPEATED IMPORT AND EXPORT OF A HIGH VALUE PRODUCT (I.E. A “CAROUSEL TRANSACTION”)
declare 
	@LookBackStartProcCall				VARCHAR(8),	
	@LookBackEndProcCall				VARCHAR(8),							
	@CurrentPeriodStartProcCall			VARCHAR(8),									
	@CurrentPeriodEndProcCall			VARCHAR(8),
	@LookBackYearStartProcCall			DATETIME,
	@LookBackYearEndProcCall			DATETIME,
	@CurrentStartProcCall				DATETIME,
	@CurrentEndProcCall					DATETIME
	
	Set 
	@LookBackStartProcCall			=  cast(convert(varchar(8),DATEADD(MM, DATEDIFF(MONTH, 0, GETDATE())-6, 0),112) as int)

	SET
	@LookBackEndProcCall			=	cast(convert(varchar(8),DATEADD(MM, DATEDIFF(MONTH, -1, GETDATE())-2, -1),112) as int)
	
	SET				
	@CurrentPeriodStartProcCall		=	cast(convert(varchar(8),DATEADD(MM, DATEDIFF(MONTH, 0, GETDATE())-1, 0),112) as int)
	
	SET									
	@CurrentPeriodEndProcCall		=	cast(convert(varchar(8), DATEADD(MM, DATEDIFF(MONTH, -1, GETDATE())-1, -1),112) as int)	 
	
	SET 
	@LookBackYearStartProcCall		=	DATEADD(MM, DATEDIFF(MONTH, 0, GETDATE())-12, 0)
	
	SET
	@LookBackYearEndProcCall		=	DATEADD(MM, DATEDIFF(MONTH, -1, GETDATE())-2, -1)
	
	SET				
	@CurrentStartProcCall			=	DATEADD(MM, DATEDIFF(MONTH, 0, GETDATE())-1, 0)	

	SET									
	@CurrentEndProcCall				=	DATEADD(MM, DATEDIFF(MONTH, -1, GETDATE())-1, -1)

	
 
 select cast(convert(varchar(8),DATEADD(MM, DATEDIFF(MONTH, 0, GETDATE())-6, 0),112) as int)
SELECT @LookBackStartProcCall
SELECT @LookBackEndProcCall
select @CurrentPeriodStartProcCall
select @CurrentPeriodEndProcCall

--CAROUSEL TRANSACTIONS
EXEC [DBO].[BOC_CAROUSEL_TRANSACTIONS]
@LOOKBACKSTART				=@LookBackStartProcCall,
@CURRPERIODSTART			=@CurrentPeriodStartProcCall,
@CURRPERIODEND				=@CurrentPeriodEndProcCall,
@CASLHRGOODSTRADETHSLD		=2,
@CASLDUGOODSTRADETHSLD		=2,
@CASLGOODSTRADETHSLD		=2,
@CASLHRDOCUMENTAMTTHSLD		=100000,
@CASLDUDOCUMENTAMTTHSLD		=100000,
@CASLDOCUMENTAMTTHSLD		=100000

--TRADE IN NEW GOODS
EXEC [BOC_TRADEINNWHRDUGOODS]
@CURRPERIODSTART			=@CurrentPeriodStartProcCall ,					
@CURRPERIODEND				=@CurrentPeriodEndProcCall,
@LOOKBACKSTART				=@LookBackStartProcCall,					
@LOOKBACKEND				=@LookBackEndProcCall,
@HRGOODSTHSLD				=1,
@DUGOODSTHSLD				=1,
@NEWGOODSTHSLD				=1,
@NEWGOODSHRCUSTTHSLD		=1

--TRADE IN NEW GEOGRAPHIES
EXEC [DBO].[BOC_TRADEINNEWGEO]
@CURRPERIODSTART			=@CurrentPeriodStartProcCall ,						
@CURRPERIODEND				=@CurrentPeriodEndProcCall,
@LOOKBACKSTART				=@LookBackStartProcCall,					
@LOOKBACKEND				=@LookBackEndProcCall,
@NEWSHIPFMTHSLD				=3,
@NEWORIGTHSLD				=3,
@NEWSHIPTOTHSLD				=3,
@HRCUSTNWGEO				=1

--TRADE IN HIGH RISK GEOGRAPHIES
EXEC [DBO].[BOC_TRADEINHRGEO]
@CURRPERIODSTART			=@CurrentPeriodStartProcCall ,						
@CURRPERIODEND				=@CurrentPeriodEndProcCall,
@HRSHIPFMCNTRYTHSLD			=1,
@HRORIGCNTRYTHSLD			=1,
@HRSHIPTOCNTRYTHSLD			=1,
@HRCUSTHRGEOTHSLD			=1

--DISCREPANCIES IN SHIPMENT INFORMATION
EXEC [DBO].[BOC_VESSELSHIPMENT_INFODISCREPANCY]
@CURRPERIODSTART			=@CurrentPeriodStartProcCall ,						
@CURRPERIODEND				=@CurrentPeriodEndProcCall

--PATTERN OF DOCUMENTARY DISCREPANCIES
EXEC [DBO].[BOC_DOCDISCREPANCIES]
@LOOKBACKSTART				=@LookBackStartProcCall,
@CURRPERIODSTART			=@CurrentPeriodStartProcCall,
@CURRPERIODEND				=@CurrentPeriodEndProcCall,
@PERDISPNCYTHSLD			=6,
@PERHRGDSDISPNCYTHSLD		=0.03,
@PERDUGDSDISPNCYTHSLD		=0.6,
@TOTDISPNCYTHSLD			=2,
@TOTNOOFDISPNCYHRGDSTHSLD	=2,
@TOTNOOFDISPNCYDUGDSTHSLD	=2


--MULTIPLE INVOICING
exec [DBO].[BOC_MULTIPLEINVOICING]
@CURRPERIODSTART			=@CurrentPeriodStartProcCall ,					
@CURRPERIODEND				=@CurrentPeriodEndProcCall

--EXCESSIVE WITHDRAWALS
EXEC [dbo].[BOC_ExcessiveWithdrawals]
	@YearStart				= @LookBackYearStartProcCall,	
	@YearEnd				= @LookBackYearEndProcCall,
	@TxnDateStart			= @CurrentStartProcCall,	
	@TxnDateEnd				= @CurrentEndProcCall,	
	@MinSingleDayWD			= 500.00,			
	@MinThreeDayAvg			= 300.00,      
	@MinDifference			= 0.500,
	@MinTxnCnt				= 2

--FOREIGN DEBIT TRANSACTIONS
EXEC [dbo].[BOC_ForeignDebit]
	@TxnDateStart			= @CurrentStartProcCall,	 
	@TxnDateEnd				= @CurrentEndProcCall,	 
	@MinForeignTxn			= 1.0,			
	@MinForeignCtry			= 1.0      
	
	
	Go