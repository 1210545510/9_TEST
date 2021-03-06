USE [Pbsa]
GO
/****** Object:  StoredProcedure [dbo].[BOC_UserAuthentication]    Script Date: 12/18/2016 09:42:44 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/* =============================================
 AuthOR:		Daneshwari
 CREATE date:	10/10/16
 DescriptiON:	
 =============================================*/


CREATE PROCEDURE [dbo].[BOC_UserAuthentication]
    @IDUser NVARCHAR(254),
    @pPass NVARCHAR(50)
AS
BEGIN


    SET NOCOUNT ON
	DECLARE @DBUSER NVARCHAR(100)
	DECLARE @responseMsg VARCHAR(250)


    IF EXISTS (SELECT TOP 1 *  FROM [dbo].[TACTICALUSER] WHERE [dbo].[TACTICALUSER].UserID=@IDUser)
    BEGIN
        SET @DBUSER=(SELECT UserID FROM [dbo].[TACTICALUSER] WHERE UserID=UPPER(@IDUser) AND PasswordHash=HASHBYTES('SHA1',@pPass+CAST(Salt AS NVARCHAR(36))))

       IF(@DBUSER IS NOT NULL)
          set  @responseMsg='SUCCESS'

		
       ELSE 
           SET @responseMsg='INVALID PASSWORD' 
    END
    ELSE
       SET @responseMsg='INVALID USERID'

SELECT @responseMsg
END





