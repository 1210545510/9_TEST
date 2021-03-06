USE [Pbsa]
GO
/****** Object:  StoredProcedure [dbo].[BOC_AddUser]    Script Date: 12/18/2016 09:43:03 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/* =============================================
 AuthOR:		Daneshwari
 CREATE date:	10/10/16
 DescriptiON:	
 =============================================*/

CREATE PROCEDURE .[dbo].[BOC_AddUser]
	@UserID NVARCHAR(100),
    @pLogintType NVARCHAR(100), 
    @pPassword NVARCHAR(64),
    @pFirstName NVARCHAR(100) = NULL, 
    @pLastName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;


--SET IDENTITY_INSERT pbsa .DBO.[TACTICALUSERS] ON ;  
    DECLARE @salt UNIQUEIDENTIFIER
	Set @salt=newid();
	
	DECLARE @responseMessage VARCHAR(250)

    BEGIN TRY
        INSERT INTO dbo.[TACTICALUSER] (UserID,LoginType, PasswordHash, Salt, FirstName, LastName)
        VALUES(UPPER(@UserID),@pLogintType, HASHBYTES('SHA1', @pPassword+CAST(@salt AS NVARCHAR(36))), @salt, @pFirstName, @pLastName)

	
       SET @responseMessage='SUCCESS'
    END TRY
    BEGIN CATCH
        SET @responseMessage=ERROR_MESSAGE() 
    END CATCH

SELECT @responseMessage
END



