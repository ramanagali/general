

-- To allow advanced options to be changed.
EXEC sp_configure 'show advanced options', 1
GO
-- To update the currently configured value for advanced options.
RECONFIGURE
GO
-- To enable the feature.
EXEC sp_configure 'xp_cmdshell', 1
GO
-- To update the currently configured value for this feature.
RECONFIGURE
GO

------------------------------------------------------------------------------------
-- Define the variables
------------------------------------------------------------------------------------

-- General variables 
Declare @DBServerName nVarchar(100)
Declare @DBName nVarchar(100)
Declare @SourceFolder nVarchar(250)
Declare @Command nVarchar(250)
DECLARE @CommandShellResultCode int	-- Result code is not really useful
DECLARE @CommandShellOutputTable TABLE (Line NVARCHAR(512)) -- Output is more useful for exception
DECLARE @SingleLineOutput nvarChar(max)

-- Single variables for cursor to use
DECLARE @sourceID int
DECLARE @sourceSqlFilename nvarchar(512)
DECLARE @sourceDepth int
DECLARE @sourceIsFile bit

-- Set the variables  
Set @DBServerName = 'DESKTOP-0362M4L\SQLEXPRESS'
Set @DBName = 'TVR_APAC'

------------------------------------------------------------------------------------
-- Create a table variable for script source folders
------------------------------------------------------------------------------------

DECLARE @RowsToProcess  int
DECLARE @CurrentRow     int
DECLARE @Sour     int

DECLARE @table1 TABLE (RowID int not null primary key identity(1,1), sourcepath nVarchar(250) ) 
INSERT into @table1 (sourcepath) VALUES ('E:\Release\DB_Deployment\01.Database\')
INSERT into @table1 (sourcepath) VALUES ('E:\Release\DB_Deployment\02.Tables\')
INSERT into @table1 (sourcepath) VALUES ('E:\Release\DB_Deployment\03.Functions\')
INSERT into @table1 (sourcepath) VALUES ('E:\Release\DB_Deployment\04.StoredProcedures\')
select @RowsToProcess = count(*) from @table1



SET @CurrentRow=0
WHILE @CurrentRow<@RowsToProcess
BEGIN
    SET @CurrentRow=@CurrentRow+1
    SELECT 
        @SourceFolder = sourcepath
        FROM @table1
        WHERE RowID=@CurrentRow

    





------------------------------------------------------------------------------------
-- Create a temp table and get the list of files from the folder
------------------------------------------------------------------------------------


-- Get all the SQL from the path
IF OBJECT_ID('tempdb..#DirectoryTree') IS NOT NULL
      DROP TABLE #DirectoryTree;

CREATE TABLE #DirectoryTree (
       ID int IDENTITY(1,1)
      ,SubDirectory nvarchar(512)
      ,Depth int
      ,IsFile bit);

INSERT #DirectoryTree (SubDirectory,Depth,IsFile)
EXEC master.sys.xp_dirtree @SourceFolder,1,1;


--SELECT * FROM #DirectoryTree
--WHERE IsFile = 1 AND RIGHT(SubDirectory,4) = '.sql'
--ORDER BY subdirectory asc


------------------------------------------------------------------------------------
-- Exec one by one 
------------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#ResultSummary') IS NOT NULL
      DROP TABLE #ResultSummary;

-- Create a result table for reference after sql being executed
CREATE TABLE #ResultSummary (
	   SqlFilename nvarchar(100),
	   ResultCode nvarchar(100),  -- for xp_cmdshell
	   ResultOutput nvarchar(max)   -- more for sqlcmd exception 
		);

-- Loop thro each SQL using cursor

DECLARE ScriptCursor CURSOR FOR
 SELECT * FROM #DirectoryTree
 WHERE Isfile = 1 AND RIGHT(SubDirectory,4) = '.sql'
 ORDER BY SubDirectory asc;
 
OPEN ScriptCursor;
FETCH NEXT FROM ScriptCursor
INTO @sourceID, @sourceSqlFilename, @sourceDepth, @sourceIsFile
 
-- Note: first one already been fetched
        
WHILE @@FETCH_STATUS = 0
   BEGIN
		-- PRINT 'Debug' + @sourceSqlFilename
     
		-- Clean up output table
        Delete from @CommandShellOutputTable
     
		-- Construct the command and execute the query           
		Set @Command = 'sqlcmd -S ' + @DBServerName + ' -d  ' + @DBName + ' -i ' + '"' +@SourceFolder + @sourceSqlFilename + '"'   
		print @Command
		
		-- Get the output and execute the command (with multiple lines output)
		INSERT INTO @CommandShellOutputTable
		EXEC @CommandShellResultCode= xp_cmdshell  @Command 
		
		
		---- Combine multiple lines output into single varible
		SELECT @SingleLineOutput = (SELECT STUFF((
		SELECT ',' + line
		FROM  @CommandShellOutputTable
		FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, ''))
    
    
	
		-- Write the 2 result variables into a temp table for summary		 
		 IF (@CommandShellResultCode = 0)
			   Insert INTO #ResultSummary(SqlFilename, ResultCode, ResultOutput)
				Values (@sourceSqlFilename, 'xp_cmdshell Executed', @SingleLineOutput)
		   ELSE
			 Insert INTO #ResultSummary(SqlFilename, ResultCode, ResultOutput) 
				Values (@sourceSqlFilename, 'xp_cmdshell Failed', @SingleLineOutput)     
     
      FETCH NEXT FROM ScriptCursor
      INTO @sourceID, @sourceSqlFilename, @sourceDepth, @sourceIsFile    
   END;
   
CLOSE ScriptCursor;
DEALLOCATE ScriptCursor;

-- Show results
Select SqlFilename, ResultCode, ISNULL(ResultOutput, 'SUCCESSFUL') as SqlcmdResult from #ResultSummary order by SqlFilename asc 

END

GO



      

