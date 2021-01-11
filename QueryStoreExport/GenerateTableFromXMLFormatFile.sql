CREATE OR ALTER Procedure [dbo].[GenerateTableFromXMLFormatFile]
	(
		@FormatFileXML XML,
		@TableName sysname,
		@DropExisting bit=0
	)
as
begin
	-- https://stackoverflow.com/questions/46134476/sql-server-format-file-can-i-use-to-generate-create-table-statement

	if @DropExisting=1 exec('drop table if exists ' + @TableName);

	SET NOCOUNT ON
	DECLARE 
		    @xmlData XML
		  , @sqlCmd NVARCHAR(1000)
		  , @dmlQuery NVARCHAR(max) = N''
		  , @crlf NVARCHAR(2) = CHAR(13)+ CHAR(10)
	DECLARE @columns table(id INT NOT NULL, colName SYSNAME NOT NULL, dataType VARCHAR(50), [Length] INT NULL, [Precision] INT NULL, [Scale] INT NULL)
	DECLARE @sql table(s VARCHAR(1000), id INT IDENTITY)

	set @xmlData = @FormatFileXML

	;WITH XMLNAMESPACES 
	(
		DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/bulkload/format',
				'http://www.w3.org/2001/XMLSchema-instance' as xsi
	)
	INSERT INTO @columns
	SELECT  x.c.value('@SOURCE', 'INT'),
			x.c.value('@NAME', 'varchar(100)'),
			SUBSTRING(x.c.value('@xsi:type', 'varchar(100)'), 4, 20),
			ISNULL(y.f.value('@MAX_LENGTH', 'INT'), y.f.value('@LENGTH', 'INT')),
			x.c.value('@PRECISION', 'INT'),
			x.c.value('@SCALE', 'INT')
	FROM @xmldata.nodes('/BCPFORMAT/ROW/COLUMN') x(c)
	JOIN @xmldata.nodes('/BCPFORMAT/RECORD/FIELD') y(f) ON x.c.value('@SOURCE', 'INT') = y.f.value('@ID', 'INT')

	UPDATE @columns SET dataType = REPLACE(dataType, 'VARYCHAR', 'VARCHAR');
	UPDATE @columns SET dataType = REPLACE(dataType, 'DATETIM4', 'SMALLDATETIME');
	UPDATE @columns SET dataType = REPLACE(dataType, 'FLT8', 'FLOAT');
	UPDATE @columns SET dataType = REPLACE(dataType, 'VARYBIN', 'VARBINARY');
	

	INSERT INTO  @sql(s) VALUES ('create table ' + QUOTENAME(@tableName) + ' (')

	INSERT INTO  @sql(s)
		SELECT @crlf 
			+ QUOTENAME([colName])+ N' ' + [dataType] 
			+ IIF([Length] IS NOT NULL AND ([dataType] LIKE 'N%CHAR' OR [dataType] LIKE '%BINARY'), '(' + CAST([Length]/2 AS VARCHAR) + ')', 
			  IIF([Length] IS NOT NULL AND [dataType] LIKE '%CHAR', '(' + CAST([Length] AS VARCHAR) + ')', 
			  
			  IIF([Length] IS NULL AND [dataType] LIKE '%CHAR', '(MAX)', 
			  IIF([Precision] IS NOT NULL AND [dataType] = 'DECIMAL', '(' + CAST([Precision] AS VARCHAR) + IIF([Scale] IS NOT NULL, ',' + CAST([Scale] AS VARCHAR), '') + ' )'
			 , '') ) ) ) + ',' 
		FROM @columns
		ORDER BY id;


	UPDATE @sql 
	   SET s = left(s, len(s) - 1) 
	 WHERE id = scope_identity()

	INSERT INTO @sql(s) VALUES( ')' )

	SELECT @dmlQuery += s 
	  FROM @sql 
	 ORDER BY id;

	exec(@dmlQuery)
end
