CREATE OR ALTER PROCEDURE usp_IncrementalShrink
@DesiredFileSize int=0,
@ShrinkChunkSize int=5,
@dbFileID int =0
as
begin
/***********************************************
Incremental Shrink for data file - SQL Server, Azure SQL, Azure Managed Instance
************************************************/
/*-------------------------------------------------
Change Log: 
	2022-07-12 - Change it from script to stored procedure
		- Add functionality to go through all data files
	2022-07-06 - more accurate current size validation.

*/-----------------------------------------------
set nocount on
declare @AllocatedSpaceMB int
declare @UsedSpaceMB int
declare @UnusedSpaceMB int
declare @ErrorIndication int=0
declare @dbFileType sysname
declare @lastSize int
declare @SqlCMD nvarchar(max)
declare @MSG nvarchar(100)
declare @iFileList table(i int)
declare @iTMP table(i int)
declare @iFileID int
declare @iCurrentSizeTarget int


set @MSG = convert(nvarchar,getdate())+' - Starting incremental shrink procedure'; raiserror(@msg,0,0) with nowait


/* @dbFileID=0 -> All Files, or actual data file ID */
insert into @iFileList select file_id from sys.database_files where type=0/*Rows*/ and (@dbFileID=0 or file_id=@dbFileID)


-- check if there is paused resumable index operation on this DB
-- existance of these types of operations block the shrink operation from reducing the file size
if (SELECT count(*) FROM sys.index_resumable_operations)>0 set @ErrorIndication=3





if @ErrorIndication=3  raiserror('[Error] Paused resumable index rebuild was detected, please abort or complete the operation before running shrink',16,0) with nowait



/*Go throgh all files pending to be shrinked*/
WHILE (select count(*) from @iFileList)>0
Begin 
	set @MSG = REPLICATE('-',50); raiserror(@msg,0,0) with nowait
	
	/*Iterate on specific file*/
	delete top (1) from @iFileList output  deleted.i into @iTMP
	select top 1 @iFileID=i from @iTMP

	set @MSG = 'Running shrink file on file ID = ' + CONVERT(varchar,@iFileID) +char(13) ; raiserror(@msg,0,0) with nowait

	SELECT 
		@AllocatedSpaceMB = SIZE/128.0
		, @UsedSpaceMB = cast(fileproperty(name, 'SpaceUsed') AS int)/128.0
		, @UnusedSpaceMB = (SIZE/128.0) - cast(fileproperty(name, 'SpaceUsed') AS int)/128.0
	FROM sys.database_files
	WHERE file_id = @iFileID

	set @MSG = char(9)+'Information about file ID = ' + CONVERT(varchar,@iFileID) ; raiserror(@msg,0,0) with nowait
	set @MSG = char(9)+char(9)+'Allocated Space MB = ' + CONVERT(varchar,@AllocatedSpaceMB) ; raiserror(@msg,0,0) with nowait
	set @MSG = char(9)+char(9)+'Used Space MB = ' + CONVERT(varchar,@UsedSpaceMB) ; raiserror(@msg,0,0) with nowait
	set @MSG = char(9)+char(9)+'Unused Space MB = ' + CONVERT(varchar,@UnusedSpaceMB) ; raiserror(@msg,0,0) with nowait
	


	set @lastSize = @AllocatedSpaceMB+1
	while @AllocatedSpaceMB > @DesiredFileSize /*check if we got the desired size*/ and @lastSize>@AllocatedSpaceMB /* check if there is progress*/ and @ErrorIndication=0
	begin
		set @MSG = char(9)+char(9)+char(9)+convert(nvarchar,getdate()) + ' - Calling ShrinkFile' ; raiserror(@msg,0,0) with nowait

		select @lastSize = size/128.0
		from sys.database_files
		where file_id=@iFileID

		/*Calculate next target size and make sure we do not go below 0*/
		set @iCurrentSizeTarget = @AllocatedSpaceMB-@ShrinkChunkSize
		set @iCurrentSizeTarget = iif(@iCurrentSizeTarget>0, @iCurrentSizeTarget,0)

		set @sqlCMD = N'dbcc shrinkfile('+cast(@iFileID as varchar(7))+','+ convert(nvarchar,@iCurrentSizeTarget) +') with no_infomsgs;'
		--print @sqlCMD
		exec(@sqlCMD)

		select @AllocatedSpaceMB = size/128.0
		from sys.database_files
		where file_id=@iFileID

		set @MSG = char(9)+char(9)+char(9)+convert(nvarchar,getdate()) + ' - ShrinkFile completed. current size is: ' + cast(@AllocatedSpaceMB as varchar(10)) + 'MB'; raiserror(@msg,0,0) with nowait
	end

	delete from @iTMP
End 

set @MSG = convert(nvarchar,getdate())+' - Finished incremental shrink procedure'; raiserror(@msg,0,0) with nowait
END

