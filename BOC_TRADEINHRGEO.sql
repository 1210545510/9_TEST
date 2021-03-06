USE [Pbsa]
GO
/****** Object:  StoredProcedure [dbo].[BOC_TRADEINHRGEO]    Script Date: 12/18/2016 09:33:33 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*=============================================
		AUTHOR:			DANESHWARI
		CREATE DATE:	08/03/16
		DESCRIPTION:	THIS SCENARIO MONITORS THE TRANSACTIONS WITH HIGH RISK COUNTRIES
=============================================*/

	CREATE PROCEDURE [dbo].[BOC_TRADEINHRGEO]
	--INPUT PARAMETERS THAT CAN BE PROVIDED WHILE RUNNING THE STORED PROCEDURE
		@CURRPERIODSTART				INT ,						-- START DATE OF CURRENT MONITORING MONTH (FORMAT:YYYYMMDD)
		@CURRPERIODEND					INT ,						-- END DATE OF CURRENT MONITORING MONTH (FORMAT:YYYYMMDD)
		@HRSHIPFMCNTRYTHSLD				INT	,						-- THRESHOLD FOR TOTAL NUMBER OF TRADES IN THE CURRENT MONTH INVOLVING A HIGH RISK SHIP FROM COUNTRY FOR A GIVEN CUSTOMER
		@HRORIGCNTRYTHSLD				INT	,						-- THRESHOLD FOR TOTAL NUMBER OF TRADES IN THE CURRENT MONTH INVOLVING A HIGH RISK COUNTRY OF ORIGIN FOR A GIVEN CUSTOMER
		@HRSHIPTOCNTRYTHSLD				INT ,						-- THRESHOLD FOR TOTAL NUMBER OF TRADES IN THE CURRENT MONTH INVOLVING A HIGH RISK SHIP TO COUNTRY FOR A GIVEN CUSTOMER
		@HRCUSTHRGEOTHSLD				INT	 						-- THRESHOLD FOR TOTAL NUMBER OF TRADES IN THE CURRENT MONTH INVOLVING A HIGH RISK COUNTRY (SHIP FROM COUNTRY/ SHIP TO COUNTRY OR COUNTRY OF ORIGIN) FOR A GIVEN HIGH RISK CUSTOMER

	
AS
BEGIN

	-- SET NOCOUNT ON ADDED TO PREVENT EXTRA RESULT SETS FROM INTERFERING WITH SELECT STATEMENTS. 
	-- THIS PROVIDES SIGNIFICANT BOOST IN PERFORMANCE
	SET NOCOUNT ON;
	

	--DELETE THE TABLES IF THEY ALREADY EXIST. THESE TABLE HOLD THE ALERT INFORMATION GENERAETED FROM PRIOR RUN
	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'TRADEINHRGEOALERTCUSTOMERS')
			BEGIN
				DROP TABLE TRADEINHRGEOALERTCUSTOMERS  
			END


	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'TRADEINHRGEOALERTTRANSACTIONS')
			BEGIN
				DROP TABLE TRADEINHRGEOALERTTRANSACTIONS  
			END


	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'TRADEINHIGHRISKGEOMAPDATA')
			BEGIN
				DROP TABLE TRADEINHIGHRISKGEOMAPDATA  
			END



	--GET THE LATEST RECORDS FROM THE TABLE: MULTI_LC_HIST
	SELECT a.ID,OLD_LC_NUMBER,LC_TYPE,LC_AMOUNT,LC_NUMBER,ISSUE_DATE
		,APPLICANT,APPLICANT_CUSTNO,APPLICANT_ACC,BENEFICIARY,	BENEFICIARY_CUSTNO,
		BENEFICIARY_ACC,ACT_GOODS_DESC,GOODSTYPE,a.ASOFDATE,COUNTRY_ORIG,SHIP_FM_COUNTRY,SHIP_TO_COUNTRY,VESSEL_NAME,VOYAGE_NUMBER
		INTO #MULTI_LC_HIST 
		FROM [9AMHSADCSQL106\SQL106$DVLP].DATA_MART_US.DBO.MULTI_LC_HIST A
		INNER JOIN (SELECT B.ID,MAX(B.ASOFDATE) 
						FROM [9AMHSADCSQL106\SQL106$DVLP].DATA_MART_US.DBO.MULTI_LC_HIST B 
						GROUP BY B.ID) TEMP(ID,ASOFDATE)
		ON A.ID=TEMP.ID
		WHERE A.ASOFDATE=TEMP.ASOFDATE



	--GET THE LATEST RECORDS FROM THE TABLE: MULTI_DRAWINGS_HIST
	SELECT A.ID,DRAWING_TYPE, COUNTRY_ORIG,SHIP_FM_COUNTRY,SHIP_TO_COUNTRY,DOCUMENT_AMOUNT,
		DOC_RECE_DT,VALUE_DATE,DATE_TIME,ACT_GOODS_DESC,GOODSTYPE,VESSEL_NAME,VOYAGE_NUMBER,DISCREPANCY,a.ASOFDATE
		INTO #MULTI_DRAWINGS_HIST 
		FROM [9AMHSADCSQL106\SQL106$DVLP].DATA_MART_US.DBO.MULTI_DRAWINGS_HIST A
		INNER JOIN (SELECT B.ID, MAX(B.ASOFDATE) 
					FROM [9AMHSADCSQL106\SQL106$DVLP].DATA_MART_US.DBO.MULTI_DRAWINGS_HIST B 
					GROUP BY B.ID) TEMP(ID,ASOFDATE)
		ON A.ID=TEMP.ID
		WHERE A.ASOFDATE=TEMP.ASOFDATE
	

	

	--UPDATE QUERY: REPLACE [F_BOC_LCGOODSTYPE_CODE] BY THE IDENTICAL TABLE FROM US_DATA_MART. CONNECT TO THE TABLE USING LINKED SERVER OBJECT
	SELECT * INTO #LCGOODSTYPE
	FROM [9AMHSADCSQL106\SQL106$DVLP].DATA_MART_US.DBO.[F_BOC_LCGOODSTYPE_CODE]


	--UPDATES GOODSTYPE FOR HISTORICAL TRANSACTIONS SINCE 2016 FEB FOR THE DRAWINGS RECORDS
	IF(getdate()<cast(cast(20170502 as char(8)) as datetime))
	UPDATE #MULTI_DRAWINGS_HIST
	SET GOODSTYPE=(SELECT A.LC_GOODSTYPE_ID FROM #LCGOODSTYPE A WHERE
	UPPER(LTRIM(RTRIM(A.GOODS_DISPLAY))) = (SELECT UPPER(LTRIM(RTRIM(A.GOODS_TYPE))) FROM GOODSREFID A WHERE
	UPPER(LTRIM(RTRIM(#MULTI_DRAWINGS_HIST.ACT_GOODS_DESC)))=UPPER(LTRIM(RTRIM(A.ACT_GOODS_DESC ))) COLLATE DATABASE_DEFAULT GROUP BY A.GOODS_TYPE) COLLATE DATABASE_DEFAULT
	) WHERE  #MULTI_DRAWINGS_HIST.GOODSTYPE IS NULL and #MULTI_DRAWINGS_HIST.DOC_RECE_DT>20160431 ;


	--UPDATES GOODSTYPE FOR HISTORICAL TRANSACTIONS SINCE 2016 FEB FOR THE LC RECORDS
	IF(getdate()<cast(cast(20170502 as char(8)) as datetime))
	UPDATE #MULTI_LC_HIST
	SET GOODSTYPE=(SELECT A.LC_GOODSTYPE_ID FROM #LCGOODSTYPE A WHERE
	UPPER(LTRIM(RTRIM(A.GOODS_DISPLAY))) = (SELECT UPPER(LTRIM(RTRIM(A.GOODS_TYPE))) FROM GOODSREFID A WHERE
	UPPER(LTRIM(RTRIM(#MULTI_LC_HIST.ACT_GOODS_DESC)))=UPPER(LTRIM(RTRIM(A.ACT_GOODS_DESC )))   COLLATE DATABASE_DEFAULT GROUP BY A.GOODS_TYPE) COLLATE DATABASE_DEFAULT
	)WHERE #MULTI_LC_HIST.GOODSTYPE IS NULL AND #MULTI_LC_HIST.ISSUE_DATE > 20160431;




	--CREATE TABLE TO HOLD ALL THE RECORDS BELONGING TO THE MONITORING PERIOD (I.E. THE CURRENT MONTH)
	CREATE TABLE #TRADEINHRGEO
		(
		ID						VARCHAR(25),
		FOCALENTITY				VARCHAR(50),
		OLD_LC_NUMBER			VARCHAR(20),
		LC_TYPE					VARCHAR(10),
		DRAWING_TYPE			VARCHAR(2),
		HIGHRISKCUSTOMER		INT DEFAULT 0,
		HIGHRISKSHIPFMCOUNTRY	INT DEFAULT 0,
		HIGHRISKORIGCOUNTRY		INT DEFAULT 0,
		HIGHRISKSHIPTOCOUNTRY	INT DEFAULT 0,
		COUNTRY_ORIG			VARCHAR(9),
		SHIP_FM_COUNTRY			VARCHAR(35),
		SHIP_TO_COUNTRY			VARCHAR(9),
		VESSEL_NAME				VARCHAR(50),
		VOYAGE_NUMBER			VARCHAR(50),
		DOCUMENT_AMOUNT			DECIMAL(19,2),
		LC_AMOUNT				DECIMAL(19,2),
		LC_NUMBER				VARCHAR(16),
		--NOTE: TRANS_DATE IS POPULATED BY THE FIELD 'ISSUE_DATE' (COLLECTION LC TYPE) OR 'DOC_RECE_DT' (LC_TYPE OTHER THAN COLLECTIONS) 
		TRANS_DATE				VARCHAR(8), 
		VALUE_DATE				VARCHAR(8),
		DATE_TIME				VARCHAR(8),
		APPLICANT				VARCHAR(100),
		APPLICANT_CUSTNO		VARCHAR(10),
		APPLICANT_ACC			INT,
		BENEFICIARY				VARCHAR(100),
		BENEFICIARY_CUSTNO		INT,
		BENEFICIARY_ACC			INT,
		ACT_GOODS_DESC			VARCHAR(100),
		GOODSTYPE				VARCHAR(100),
		)


	--INSERT THE REQUIRED FIELDS INTO TABLE #TRADEINHRGEO FOR THE TRANSACTIONS WHOSE LC TYPES DO NOT BEGIN WITH 'C' I.E. THE LC TYPES OTHER THAN COLLECTIONS
		INSERT INTO #TRADEINHRGEO (ID,FOCALENTITY,OLD_LC_NUMBER,LC_TYPE,DRAWING_TYPE,COUNTRY_ORIG,SHIP_FM_COUNTRY,SHIP_TO_COUNTRY,VESSEL_NAME,VOYAGE_NUMBER,
		DOCUMENT_AMOUNT,LC_AMOUNT,LC_NUMBER,TRANS_DATE,VALUE_DATE,DATE_TIME,APPLICANT,APPLICANT_CUSTNO,APPLICANT_ACC,BENEFICIARY,BENEFICIARY_CUSTNO,BENEFICIARY_ACC,
		ACT_GOODS_DESC,GOODSTYPE)
			SELECT MD.ID,
				CASE WHEN (ML.LC_TYPE LIKE 'I%' OR ML.LC_TYPE LIKE 'SO%')
					THEN
						CASE 
						WHEN APPLICANT_CUSTNO IS NOT NULL THEN APPLICANT_CUSTNO 
						WHEN APPLICANT_CUSTNO IS NULL AND APPLICANT IS NOT NULL THEN APPLICANT
						ELSE ML.ID  
						END

				ELSE 
						CASE 
						WHEN BENEFICIARY_CUSTNO IS NOT NULL THEN BENEFICIARY_CUSTNO 
						WHEN BENEFICIARY_CUSTNO IS NULL AND BENEFICIARY IS NOT NULL THEN BENEFICIARY
						ELSE ML.ID  
						END
				END,
		ML.OLD_LC_NUMBER,ML.LC_TYPE,MD.DRAWING_TYPE, MD.COUNTRY_ORIG,MD.SHIP_FM_COUNTRY,MD.SHIP_TO_COUNTRY,MD.VESSEL_NAME,MD.VOYAGE_NUMBER,MD.DOCUMENT_AMOUNT,
		ML.LC_AMOUNT,ML.LC_NUMBER,MD.DOC_RECE_DT,MD.VALUE_DATE,MD.DATE_TIME,ML.APPLICANT,ML.APPLICANT_CUSTNO,ML.APPLICANT_ACC,ML.BENEFICIARY,ML.BENEFICIARY_CUSTNO,ML.BENEFICIARY_ACC, 
		MD.ACT_GOODS_DESC,MD.GOODSTYPE
		FROM #MULTI_DRAWINGS_HIST MD
		INNER JOIN #MULTI_LC_HIST ML
		ON LEFT(MD.ID,12)=ML.ID
		WHERE ML.LC_TYPE IS NOT NULL
		--CONDITIONAL STATEMENTS FOR TRANSACTIONS
		AND ML.LC_TYPE <> 'RUS' 
		AND ML.LC_TYPE NOT LIKE 'C%' AND ML.LC_TYPE NOT LIKE 'ET%'
		AND MD.DOC_RECE_DT BETWEEN @CURRPERIODSTART AND @CURRPERIODEND      
		ORDER BY MD.ID



		--INSERT THE REQUIRED FIELDS INTO TABLE #TRADEINHRGEO FOR THE TRANSACTIONS WHOSE LC TYPES BEGIN WITH 'C' (COLLECTION LC TYPE)
		INSERT INTO #TRADEINHRGEO (ID,FOCALENTITY,OLD_LC_NUMBER,LC_TYPE,DRAWING_TYPE,COUNTRY_ORIG,SHIP_FM_COUNTRY,SHIP_TO_COUNTRY,VESSEL_NAME,VOYAGE_NUMBER,
		DOCUMENT_AMOUNT,LC_AMOUNT,LC_NUMBER,TRANS_DATE,VALUE_DATE,DATE_TIME,APPLICANT,APPLICANT_CUSTNO,APPLICANT_ACC,BENEFICIARY,
		BENEFICIARY_CUSTNO,BENEFICIARY_ACC, ACT_GOODS_DESC,GOODSTYPE) 
			SELECT MD.ID,
					CASE 
					WHEN APPLICANT_CUSTNO IS NOT NULL THEN APPLICANT_CUSTNO 
					WHEN APPLICANT_CUSTNO IS NULL AND APPLICANT IS NOT NULL THEN APPLICANT
					ELSE ML.ID  
					END,
		ML.OLD_LC_NUMBER,ML.LC_TYPE,MD.DRAWING_TYPE,ML.COUNTRY_ORIG,ML.SHIP_FM_COUNTRY,ML.SHIP_TO_COUNTRY,ML.VESSEL_NAME,ML.VOYAGE_NUMBER,
		MD.DOCUMENT_AMOUNT,ML.LC_AMOUNT,ML.LC_NUMBER,ML.ISSUE_DATE,MD.VALUE_DATE,MD.DATE_TIME,ML.APPLICANT,ML.APPLICANT_CUSTNO,ML.APPLICANT_ACC,ML.BENEFICIARY,
		ML.BENEFICIARY_CUSTNO,ML.BENEFICIARY_ACC,ML.ACT_GOODS_DESC,ML.GOODSTYPE 
		FROM #MULTI_DRAWINGS_HIST MD
		INNER JOIN #MULTI_LC_HIST ML
		ON LEFT(MD.ID,12)=ML.ID
		WHERE  ML.ISSUE_DATE BETWEEN @CURRPERIODSTART AND @CURRPERIODEND      
		AND ML.LC_TYPE LIKE 'C%' 




	--FLAG THE RECORDS WITH HIGH RISK SHIP_FM_COUNTRY/ORIGIN_COUNTRY AND HIGH RISK CUSTOMER PROFILE
	UPDATE #TRADEINHRGEO 
		SET HIGHRISKSHIPFMCOUNTRY	=CASE
										WHEN EXISTS (SELECT 1 FROM [Pcdb].[dbo].[ListValue] A
										WHERE (UPPER(LTRIM(RTRIM(#TRADEINHRGEO.SHIP_FM_COUNTRY))) = UPPER(LTRIM(RTRIM(A.CODE)))) 
										AND A.ListTypeCode ='HRCTRY' AND UPPER(LTRIM(RTRIM(#TRADEINHRGEO.SHIP_FM_COUNTRY)))<>'ZZ')
										THEN 1
										ELSE 0
									END,
			HIGHRISKORIGCOUNTRY		=CASE
										WHEN EXISTS (SELECT 1 FROM [Pcdb].[dbo].[ListValue] A  
										WHERE (UPPER(LTRIM(RTRIM(#TRADEINHRGEO.COUNTRY_ORIG))) = UPPER(LTRIM(RTRIM(A.CODE)))) 
										AND A.ListTypeCode ='HRCTRY' AND UPPER(LTRIM(RTRIM(#TRADEINHRGEO.COUNTRY_ORIG)))<>'ZZ')
										THEN 1
										ELSE 0
									END,
			HIGHRISKSHIPTOCOUNTRY	=CASE
										WHEN EXISTS (SELECT 1 FROM [Pcdb].[dbo].[ListValue]  A 
										WHERE (UPPER(LTRIM(RTRIM(#TRADEINHRGEO.SHIP_TO_COUNTRY))) = UPPER(LTRIM(RTRIM(A.CODE)))) 
										AND A.ListTypeCode ='HRCTRY' AND UPPER(LTRIM(RTRIM(#TRADEINHRGEO.SHIP_TO_COUNTRY)))<>'ZZ')
										THEN 1
										ELSE 0
									END,
			 HIGHRISKCUSTOMER		=CASE
										WHEN EXISTS (SELECT 1 FROM DBO.CUSTOMER WHERE ISNUMERIC(#TRADEINHRGEO.FOCALENTITY)=1 AND CUSTOMER.ID = #TRADEINHRGEO.FOCALENTITY   
										AND UPPER(CUSTOMER.RISKCLASS) IN ('H1','H2','HIGH'))
										THEN 1
										ELSE 0
									END;




			--CREATE TEMPROPRY TABLE TO HOLD ALL THE COMPUTATIONS W.R.T ALL THE CUSTOMERS
			CREATE TABLE #TT1 (
				FOCALENTITY				VARCHAR(50),
				HIGHRISKCUSTOMER		INT DEFAULT 0,
				HIGHRISKSHIPFMCOUNTRY	INT DEFAULT 0,
				HIGHRISKORIGCOUNTRY		INT DEFAULT 0,
				HIGHRISKSHIPTOCOUNTRY	INT DEFAULT 0,
				ALERTINGCONDTITION		VARCHAR (25)
			)


			--COMPUTE THE REQUIRED FIELDS AND INESRT INTO #TT1
			INSERT INTO #TT1 (FOCALENTITY,HIGHRISKSHIPFMCOUNTRY,HIGHRISKORIGCOUNTRY,HIGHRISKSHIPTOCOUNTRY,HIGHRISKCUSTOMER)
				SELECT  FOCALENTITY,SUM(CAST(HIGHRISKSHIPFMCOUNTRY AS INT)),SUM(CAST(HIGHRISKORIGCOUNTRY AS INT)),SUM(CAST(HIGHRISKSHIPTOCOUNTRY AS INT)),
				MAX(CAST(HIGHRISKCUSTOMER AS INT)) 
				FROM #TRADEINHRGEO
				GROUP BY FOCALENTITY 


			--CREATE TABLE TO STORE ALL THE ALERTED TRANSACTIONS 
			CREATE TABLE #TRADEINHRGEO_ALERTS(
			ID						VARCHAR(25),
			FOCALENTITY				VARCHAR(50),
			OLD_LC_NUMBER			VARCHAR(20),
			ALERTINGCONDTITION		VARCHAR (25),
			HIGHRISKCUSTOMER		INT DEFAULT 0,
			HIGHRISKSHIPFMCOUNTRY	INT DEFAULT 0,
			HIGHRISKORIGCOUNTRY		INT DEFAULT 0,
			HIGHRISKSHIPTOCOUNTRY	INT DEFAULT 0,
			LC_TYPE					VARCHAR(10),
			DRAWING_TYPE			VARCHAR(2),
			COUNTRY_ORIG			VARCHAR(9),
			SHIP_FM_COUNTRY			VARCHAR(35),
			SHIP_TO_COUNTRY			VARCHAR(9),
			DOCUMENT_AMOUNT			DECIMAL(19,2),
			LC_AMOUNT				DECIMAL(19,2),
			LC_NUMBER				VARCHAR(16),
			TRANS_DATE				VARCHAR(8),
			VALUE_DATE				VARCHAR(8),
			DATE_TIME				VARCHAR(8),
			APPLICANT				VARCHAR(45),
			APPLICANT_CUSTNO		VARCHAR(10),
			APPLICANT_ACC			INT,
			BENEFICIARY				VARCHAR(100),
			BENEFICIARY_CUSTNO		INT,
			BENEFICIARY_ACC			INT,
			ACT_GOODS_DESC			VARCHAR(100),
			GOODSTYPE				VARCHAR(100)
		)


			--THE NEXT 3 SNIPPETS INSERT THE TRANSACTIONS WHICH BREACH THE THRESHOLD FOR HIGH RISK CUSTOMERS AND HIGH RISK SHIP FROM COUNTRY, ORIGIN COUNTRY AND SHIP TO COUNTRY
			INSERT INTO #TRADEINHRGEO_ALERTS 
			SELECT A.ID,A.FOCALENTITY,A.OLD_LC_NUMBER,'HRCUSTHRSHIPFMCNTRY',A.HIGHRISKCUSTOMER,A.HIGHRISKSHIPFMCOUNTRY ,
				A.HIGHRISKORIGCOUNTRY,A.HIGHRISKSHIPTOCOUNTRY,A.LC_TYPE,A.DRAWING_TYPE,A.COUNTRY_ORIG,A.SHIP_FM_COUNTRY,A.SHIP_TO_COUNTRY ,A.DOCUMENT_AMOUNT,
				A.LC_AMOUNT,A.LC_NUMBER,A.TRANS_DATE,A.VALUE_DATE,A.DATE_TIME,A.APPLICANT,A.APPLICANT_CUSTNO,A.APPLICANT_ACC,
				A.BENEFICIARY,A.BENEFICIARY_CUSTNO ,A.BENEFICIARY_ACC,A.ACT_GOODS_DESC, A.GOODSTYPE
			FROM #TRADEINHRGEO A
			INNER JOIN #TT1 B
			ON LTRIM(RTRIM(A.FOCALENTITY))=LTRIM(RTRIM(B.FOCALENTITY))
			WHERE (B.HIGHRISKCUSTOMER=1 AND B.HIGHRISKSHIPFMCOUNTRY>=@HRCUSTHRGEOTHSLD )
			AND A.HIGHRISKCUSTOMER=1 AND A.HIGHRISKSHIPFMCOUNTRY=1

			INSERT INTO #TRADEINHRGEO_ALERTS 
			SELECT A.ID,A.FOCALENTITY,A.OLD_LC_NUMBER,'HRCUSTHRORIGCNTRY',A.HIGHRISKCUSTOMER,A.HIGHRISKSHIPFMCOUNTRY ,
				A.HIGHRISKORIGCOUNTRY,A.HIGHRISKSHIPTOCOUNTRY,A.LC_TYPE,A.DRAWING_TYPE,A.COUNTRY_ORIG,A.SHIP_FM_COUNTRY,A.SHIP_TO_COUNTRY ,A.DOCUMENT_AMOUNT,
				A.LC_AMOUNT,A.LC_NUMBER,A.TRANS_DATE,A.VALUE_DATE,A.DATE_TIME,A.APPLICANT,A.APPLICANT_CUSTNO,A.APPLICANT_ACC,
				A.BENEFICIARY,A.BENEFICIARY_CUSTNO ,A.BENEFICIARY_ACC,A.ACT_GOODS_DESC,A.GOODSTYPE
			FROM #TRADEINHRGEO A
			INNER JOIN #TT1 B
			ON LTRIM(RTRIM(A.FOCALENTITY))=LTRIM(RTRIM(B.FOCALENTITY))
			WHERE (B.HIGHRISKCUSTOMER=1 AND B.HIGHRISKORIGCOUNTRY>=@HRCUSTHRGEOTHSLD)
			AND A.HIGHRISKCUSTOMER=1 AND A.HIGHRISKORIGCOUNTRY=1


			INSERT INTO #TRADEINHRGEO_ALERTS 
			SELECT A.ID,A.FOCALENTITY,A.OLD_LC_NUMBER,'HRCUSTHRSHIPTOCNTRY',A.HIGHRISKCUSTOMER,A.HIGHRISKSHIPFMCOUNTRY ,
				A.HIGHRISKORIGCOUNTRY,A.HIGHRISKSHIPTOCOUNTRY,A.LC_TYPE,A.DRAWING_TYPE,A.COUNTRY_ORIG,A.SHIP_FM_COUNTRY,A.SHIP_TO_COUNTRY ,A.DOCUMENT_AMOUNT,
				A.LC_AMOUNT,A.LC_NUMBER,A.TRANS_DATE,A.VALUE_DATE,A.DATE_TIME,A.APPLICANT,A.APPLICANT_CUSTNO,A.APPLICANT_ACC,
				A.BENEFICIARY,A.BENEFICIARY_CUSTNO ,A.BENEFICIARY_ACC,A.ACT_GOODS_DESC, A.GOODSTYPE
			FROM #TRADEINHRGEO A
			INNER JOIN #TT1 B
			ON LTRIM(RTRIM(A.FOCALENTITY))=LTRIM(RTRIM(B.FOCALENTITY))
			WHERE (B.HIGHRISKCUSTOMER =1 AND B.HIGHRISKSHIPTOCOUNTRY >=@HRCUSTHRGEOTHSLD) 
			AND A.HIGHRISKCUSTOMER=1 AND A.HIGHRISKSHIPTOCOUNTRY=1


			--INSERT THE TRANSACTIONS WHICH BREACH THE THERSHOLD FOR HIGH RISK SHIP TO COUNTRY
			INSERT INTO #TRADEINHRGEO_ALERTS 
			SELECT A.ID,A.FOCALENTITY,A.OLD_LC_NUMBER,'HRSHIPTOCNTRY',A.HIGHRISKCUSTOMER,A.HIGHRISKSHIPFMCOUNTRY ,
				A.HIGHRISKORIGCOUNTRY,A.HIGHRISKSHIPTOCOUNTRY,A.LC_TYPE,A.DRAWING_TYPE,A.COUNTRY_ORIG,A.SHIP_FM_COUNTRY,A.SHIP_TO_COUNTRY ,A.DOCUMENT_AMOUNT,
				A.LC_AMOUNT,A.LC_NUMBER,A.TRANS_DATE,A.VALUE_DATE,A.DATE_TIME,A.APPLICANT,A.APPLICANT_CUSTNO,A.APPLICANT_ACC,
				A.BENEFICIARY,A.BENEFICIARY_CUSTNO ,A.BENEFICIARY_ACC,A.ACT_GOODS_DESC, A.GOODSTYPE
			FROM #TRADEINHRGEO A
			INNER JOIN #TT1 B
			ON LTRIM(RTRIM(A.FOCALENTITY))=LTRIM(RTRIM(B.FOCALENTITY))
			WHERE (B.HIGHRISKSHIPTOCOUNTRY >=@HRSHIPTOCNTRYTHSLD) 
			AND A.HIGHRISKSHIPTOCOUNTRY=1


			--INSERT THE TRANSACTIONS WHICH BREACH THE THERSHOLD FOR HIGH RISK SHIP FROM COUNTRY
			INSERT INTO #TRADEINHRGEO_ALERTS 
			SELECT A.ID,A.FOCALENTITY,A.OLD_LC_NUMBER,'HRSHIPFMCNTRY',A.HIGHRISKCUSTOMER,A.HIGHRISKSHIPFMCOUNTRY ,
				A.HIGHRISKORIGCOUNTRY,A.HIGHRISKSHIPTOCOUNTRY,A.LC_TYPE,A.DRAWING_TYPE,A.COUNTRY_ORIG,A.SHIP_FM_COUNTRY,A.SHIP_TO_COUNTRY ,A.DOCUMENT_AMOUNT,
				A.LC_AMOUNT,A.LC_NUMBER,A.TRANS_DATE,A.VALUE_DATE,A.DATE_TIME,A.APPLICANT,A.APPLICANT_CUSTNO,A.APPLICANT_ACC,
				A.BENEFICIARY,A.BENEFICIARY_CUSTNO ,A.BENEFICIARY_ACC,A.ACT_GOODS_DESC,A.GOODSTYPE
			FROM #TRADEINHRGEO A
			INNER JOIN #TT1 B
			ON LTRIM(RTRIM(A.FOCALENTITY))=LTRIM(RTRIM(B.FOCALENTITY))
			WHERE (B.HIGHRISKSHIPFMCOUNTRY >=@HRSHIPFMCNTRYTHSLD) 
			AND A.HIGHRISKSHIPFMCOUNTRY=1


			--INSERT THE TRANSACTIONS WHICH BREACH THE THERSHOLD FOR HIGH RISK ORIGIN COUNTRY
			INSERT INTO #TRADEINHRGEO_ALERTS 
			SELECT A.ID,A.FOCALENTITY,A.OLD_LC_NUMBER,'HRORIGCNTRY',A.HIGHRISKCUSTOMER,A.HIGHRISKSHIPFMCOUNTRY ,
				A.HIGHRISKORIGCOUNTRY,A.HIGHRISKSHIPTOCOUNTRY,A.LC_TYPE,A.DRAWING_TYPE,A.COUNTRY_ORIG,A.SHIP_FM_COUNTRY,A.SHIP_TO_COUNTRY ,A.DOCUMENT_AMOUNT,
				A.LC_AMOUNT,A.LC_NUMBER,A.TRANS_DATE,A.VALUE_DATE,A.DATE_TIME,A.APPLICANT,A.APPLICANT_CUSTNO,A.APPLICANT_ACC,
				A.BENEFICIARY,A.BENEFICIARY_CUSTNO ,A.BENEFICIARY_ACC,A.ACT_GOODS_DESC,A.GOODSTYPE
			FROM #TRADEINHRGEO A
			INNER JOIN #TT1 B
			ON LTRIM(RTRIM(A.FOCALENTITY))=LTRIM(RTRIM(B.FOCALENTITY))
			WHERE (B.HIGHRISKORIGCOUNTRY >=@HRORIGCNTRYTHSLD) 
			AND A.HIGHRISKORIGCOUNTRY=1


			--INSERT THE DISTINCT FOCALENTITY AND ALERTING CONDITIONS INTO A NEW TABLE 	
			SELECT DISTINCT FOCALENTITY,ALERTINGCONDTITION INTO #TT2 FROM #TRADEINHRGEO_ALERTS

		

		--INSERT THE FOCALENTITY AND ALL THE CORRESPONDING ALERTED CONDITIONS INTO A NEW TABLE (ALERTING CONDITIONS ARE DISPLAYED IN A SINGLE FIELD FOR A GIVEN FOCALENTITY)
		SELECT C.FOCALENTITY,
				   LEFT(C.ALERTINGCONDITIONS,LEN(C.ALERTINGCONDITIONS)-1) AS 'ALERTINGCONDITIONS' INTO #TT3
			FROM
				(
						SELECT DISTINCT B.FOCALENTITY, 
							   (
									SELECT A.ALERTINGCONDTITION + ',' AS [text()]
									FROM #TT2 A
									WHERE A.FOCALENTITY = B.FOCALENTITY
									ORDER BY A.FOCALENTITY
									FOR XML PATH ('')
								) ALERTINGCONDITIONS
							FROM #TT2 B
			)C

			--INSERT THE ID AND ALL THE CORRESPONDING ALERTED CONDITIONS INTO A NEW TABLE (ALERTING CONDITIONS ARE DISPLAYED IN A SINGLE FIELD FOR A GIVEN ID)
					SELECT C.ID,
				   LEFT(C.ALERTINGCONDITIONS,LEN(C.ALERTINGCONDITIONS)-1) AS 'ALERTINGCONDITIONS' INTO #HISTORICALTRANSACTIONDATA
			FROM
				(
						SELECT DISTINCT B.ID, 
							   (
									SELECT A.ALERTINGCONDTITION + ',' AS [text()]
									FROM #TRADEINHRGEO_ALERTS A
									WHERE A.ID = B.ID
									ORDER BY A.ID
									FOR XML PATH ('')
								) ALERTINGCONDITIONS
							FROM #TRADEINHRGEO_ALERTS B
			)C



			--INSERT ALL THE TRANSACTIONS FROM THE CURRENT RUN TO THE HISTORICAL TRANSACTION TABLE FOR THE ALERTED CUSTOMERS
			INSERT INTO HISTORICALTRANSACTIONS
			SELECT DISTINCT [dbo].[BOC_ReplaceSpaces](A.FOCALENTITY) AS FOCALENTITY,A.LC_NUMBER,A.ID,'TRADE_IN_HIGH_RISK_GEO' AS SCENARIO,D.ALERTINGCONDITIONS,A.OLD_LC_NUMBER,A.APPLICANT,A.APPLICANT_CUSTNO,
			A.LC_TYPE,A.DRAWING_TYPE,A.DOCUMENT_AMOUNT,A.LC_AMOUNT,A.COUNTRY_ORIG,A.SHIP_FM_COUNTRY,A.SHIP_TO_COUNTRY,E.VESSEL_NAME,E.VOYAGE_NUMBER,E.DISCREPANCY,
			A.TRANS_DATE,A.BENEFICIARY,A.BENEFICIARY_CUSTNO,REPLACE(LTRIM(RTRIM(A.ACT_GOODS_DESC)),' ','_') AS ACT_GOODS_DESC,[dbo].[BOC_ReplaceSpaces](C.GOODS_DISPLAY)
			AS GOODSTYPE,DATENAME(MONTH, CAST(CONVERT(CHAR(8),20161001) AS DATETIME))+ ' '+DATENAME(YEAR, CAST(CONVERT(CHAR(8),20161001) AS DATETIME)) AS ALERT_MONTH,
			GETDATE() AS RUN_MONTH
			FROM #TRADEINHRGEO A
			INNER JOIN #TT3 B
			ON A.FOCALENTITY=B.FOCALENTITY
			LEFT JOIN #LCGOODSTYPE C
			ON CAST(A.GOODSTYPE AS FLOAT)=CAST(C.LC_GOODSTYPE_ID AS FLOAT)
			LEFT JOIN #HISTORICALTRANSACTIONDATA D
			ON A.ID=D.ID
			LEFT JOIN #MULTI_DRAWINGS_HIST E
			ON A.ID=E.ID COLLATE DATABASE_DEFAULT
			AND NOT EXISTS (SELECT 1 FROM HISTORICALTRANSACTIONS B WHERE B.ID=A.ID AND B.ALERTINGCONDITIONS=D.ALERTINGCONDITIONS
			AND B.ALERT_MONTH=DATENAME(MONTH, CAST(CONVERT(CHAR(8),20161001) AS DATETIME))+ ' '+DATENAME(YEAR, CAST(CONVERT(CHAR(8),20161001) AS DATETIME))
			)

		
			--INSERT CUSTOMER LEVEL INFORMATION FOR ALERTED CUSTOMERS INTO A NEW TABLE
			SELECT [dbo].[BOC_ReplaceSpaces](A.FOCALENTITY) AS FOCALENTITY,A.ALERTINGCONDITIONS,B.HIGHRISKCUSTOMER,B.HIGHRISKSHIPFMCOUNTRY,B.HIGHRISKORIGCOUNTRY,B.HIGHRISKSHIPTOCOUNTRY 
			INTO PBSA.DBO.TRADEINHRGEOALERTCUSTOMERS
			 FROM #TT3 A
			INNER JOIN #TT1 B
			ON A.FOCALENTITY=B.FOCALENTITY
			


			--INSERT TRANSACTION LEVEL INFORMATION FOR ALERTED CUSTOMERS INTO A NEW TABLE. 
			SELECT DISTINCT A.ID,[dbo].[BOC_ReplaceSpaces](A.FOCALENTITY) AS FOCALENTITY,A.OLD_LC_NUMBER,A.HIGHRISKCUSTOMER,A.HIGHRISKSHIPFMCOUNTRY ,
			A.HIGHRISKORIGCOUNTRY,A.HIGHRISKSHIPTOCOUNTRY,A.LC_TYPE,A.DRAWING_TYPE,A.COUNTRY_ORIG,A.SHIP_FM_COUNTRY,A.SHIP_TO_COUNTRY ,A.DOCUMENT_AMOUNT,
			A.LC_AMOUNT,A.LC_NUMBER,A.TRANS_DATE,A.VALUE_DATE,A.DATE_TIME,A.APPLICANT,A.APPLICANT_CUSTNO,A.APPLICANT_ACC,
			A.BENEFICIARY,A.BENEFICIARY_CUSTNO ,A.BENEFICIARY_ACC,REPLACE(LTRIM(RTRIM(A.ACT_GOODS_DESC)),' ','_') AS ACT_GOODS_DESC,[dbo].[BOC_ReplaceSpaces](B.GOODS_DISPLAY) AS GOODSTYPE
			INTO PBSA.DBO.TRADEINHRGEOALERTTRANSACTIONS 
			FROM #TRADEINHRGEO_ALERTS A 
			LEFT JOIN #LCGOODSTYPE B
			ON CAST(A.GOODSTYPE AS FLOAT)=CAST(B.LC_GOODSTYPE_ID AS FLOAT)
	
			--INSERT ALL THE TRANSACTIONS MADE BY THE ALERTED CUSTOMER DURING THE CURRENT PERIOD. ALSO FLAG THE ALERTED TRANSACTIONS
			SELECT A.ID ,[dbo].[BOC_ReplaceSpaces](A.FOCALENTITY) AS FOCALENTITY,A.OLD_LC_NUMBER,A.LC_TYPE ,A.DRAWING_TYPE ,A.COUNTRY_ORIG ,
			A.SHIP_FM_COUNTRY ,A.SHIP_TO_COUNTRY ,CAST(A.DOCUMENT_AMOUNT AS VARCHAR) AS DOCUMENT_AMOUNT,CAST(A.LC_AMOUNT AS VARCHAR) AS LC_AMOUNT,A.LC_NUMBER ,A.TRANS_DATE,
			REPLACE(LTRIM(RTRIM(A.APPLICANT)),' ', '_') AS APPLICANT ,CAST(A.APPLICANT_CUSTNO AS VARCHAR) AS APPLICANT_CUSTNO ,CAST(A.APPLICANT_ACC AS VARCHAR) AS APPLICANT_ACC,REPLACE(LTRIM(RTRIM(A.BENEFICIARY)),' ','_') AS BENEFICIARY ,
			CAST(A.BENEFICIARY_CUSTNO AS VARCHAR) AS BENEFICIARY_CUSTNO,REPLACE(LTRIM(RTRIM(A.ACT_GOODS_DESC)),' ','_') AS ACT_GOODS_DESC,[dbo].[BOC_ReplaceSpaces](B.GOODS_DISPLAY) AS GOODSTYPE,
			ISNULL(TR.HIGHRISKCUSTOMER,0) AS HIGHRISKCUSTOMER, 
			ISNULL(TR.HIGHRISKSHIPFMCOUNTRY,0) AS HIGHRISKSHIPFMCOUNTRY, 
			ISNULL(TR.HIGHRISKORIGCOUNTRY,0) AS HIGHRISKORIGCOUNTRY, ISNULL(TR.HIGHRISKSHIPTOCOUNTRY,0) AS HIGHRISKSHIPTOCOUNTRY
			INTO PBSA.DBO.TRADEINHIGHRISKGEOMAPDATA
			FROM #TRADEINHRGEO A
			LEFT JOIN TRADEINHRGEOALERTTRANSACTIONS TR
			ON  A.ID=TR.ID 
			LEFT JOIN #LCGOODSTYPE B
			ON CAST(A.GOODSTYPE AS FLOAT)=CAST(B.LC_GOODSTYPE_ID AS FLOAT)



			--INSERT CUSTOMER LEVEL INFORMATION W.R.T THE ALERTED CUSTOMERS IN THE HISTORICAL ALERTS TABLE
			INSERT INTO PBSA.DBO.CONSOLIDATEDALERTS
			SELECT  'TRADE_IN_HIGH_RISK_GEO' AS ALERT_NAME,ALERTINGCONDITIONS,[dbo].[BOC_ReplaceSpaces](A.FOCALENTITY) AS FOCALENTITY,CUSTOMERNAME,DATENAME(MONTH, CAST(CONVERT(CHAR(8),@CURRPERIODSTART) AS DATETIME))+ ' '+DATENAME(YEAR, CAST(CONVERT(CHAR(8),@CURRPERIODSTART) AS DATETIME)),GETDATE()  FROM TRADEINHRGEOALERTCUSTOMERS A
			LEFT JOIN 
			(SELECT FOCALENTITY, MAX(CUSTOMERNAME) AS CUSTOMERNAME FROM 
			(SELECT FOCALENTITY, 
			CASE 
			WHEN FOCALENTITY=CAST(BENEFICIARY_CUSTNO AS VARCHAR) THEN BENEFICIARY
			WHEN FOCALENTITY=CAST(APPLICANT_CUSTNO AS VARCHAR) THEN APPLICANT 
			WHEN UPPER(LTRIM(RTRIM(FOCALENTITY)))=UPPER(LTRIM(RTRIM(BENEFICIARY))) THEN BENEFICIARY 
			WHEN UPPER(LTRIM(RTRIM(FOCALENTITY)))=UPPER(LTRIM(RTRIM(APPLICANT))) THEN APPLICANT 
			END AS CUSTOMERNAME FROM TRADEINHRGEOALERTTRANSACTIONS)B 
			GROUP BY FOCALENTITY) C
			ON A.FOCALENTITY=C.FOCALENTITY
			WHERE NOT EXISTS (SELECT 1 FROM CONSOLIDATEDALERTS B WHERE  B.ALERTING_CONDITION= ALERTINGCONDITIONS
			AND B.ALERT_MONTH= DATENAME(MONTH, CAST(CONVERT(CHAR(8),@CURRPERIODSTART) AS DATETIME))+ ' '+DATENAME(YEAR, CAST(CONVERT(CHAR(8),@CURRPERIODSTART) AS DATETIME))
			AND  B.FOCALENTITY=A.FOCALENTITY)



END




