if object_id('AzureSQLMaintenance') is null
	exec('create procedure AzureSQLMaintenance as /*dummy procedure body*/ select 1;')	
GO
alter Procedure AzureSQLMaintenance
	(
		@operation nvarchar(50) = null
	)
as
begin
	set nocount on

	if @operation not in ('index','statistics','all') or @operation is null
	begin
		raiserror('Supply operation to perform',0,0)
		raiserror('"index" to perform index maintenance',0,0)
		raiserror('"statistics" to perform statistics maintenance',0,0)
		raiserror('"all" to perform indexes and statistics maintenance',0,0)
	end
	

	/*
		drop table if exists #idxBefore
		drop table if exists #statsBefore
		drop table if exists #cmdQueue
	*/
		create table #cmdQueue (txtCMD nvarchar(max))
	

	if @operation in('index','all')
	begin
		raiserror('Get index information...(wait)',0,0) with nowait;
		/* Get Index Information */
		select 
			ObjectSchema = OBJECT_SCHEMA_NAME(i.object_id)
			,ObjectName = object_name(i.object_id) 
			,i.avg_fragmentation_in_percent
			,i.page_count
			,i.index_id
			,i.partition_number
			,i.index_type_desc
			,i.avg_page_space_used_in_percent
			,i.record_count
			,i.ghost_record_count
			,i.forwarded_record_count
		into #idxBefore
		from sys.dm_db_index_physical_stats(DB_ID(),NULL, NULL, NULL ,'limited') i
		order by i.avg_fragmentation_in_percent desc, page_count desc

		/* create queue for update indexes */
		insert into #cmdQueue
		select 
		txtCMD = 
		case when avg_fragmentation_in_percent>10 and avg_fragmentation_in_percent<30 then
			'ALTER INDEX ALL ON [' + ObjectSchema + '].[' + ObjectName + '] REORGANIZE;'
			else
			'ALTER INDEX ALL ON [' + ObjectSchema + '].[' + ObjectName + '] REBUILD WITH(ONLINE=ON);'
		end
		from #idxBefore
		where 
			index_id>0 /*disable heaps*/ 
			and index_id < 1000 /* disable XML indexes */
			and page_count> 1000 /* not small tables */
			and avg_fragmentation_in_percent>5
	end

	if @operation in('statistics','all')
	begin 
		/*Gets Stats for database*/
		raiserror('Get statistics information...',0,0) with nowait;
		select 
			ObjectSchema = OBJECT_SCHEMA_NAME(s.object_id)
			,ObjectName = object_name(s.object_id) 
			,StatsName = s.name
			,sp.last_updated
			,sp.rows
			,sp.rows_sampled
			,sp.modification_counter
		into #statsBefore
		from sys.stats s cross apply sys.dm_db_stats_properties(s.object_id,s.stats_id) sp 
		where s.object_id>100 and sp.modification_counter>0
		order by sp.last_updated asc

		/* create queue for update stats */
		insert into #cmdQueue
		select 
		txtCMD = 'UPDATE STATISTICS [' + ObjectSchema + '].[' + ObjectName + '] WITH FULLSCAN;'
		from #statsBefore
	end


if @operation in('statistics','index','all')
	begin 
		/* iterate through all stats */
		raiserror('Start executing commands...',0,0) with nowait
		declare @SQLCMD nvarchar(max)
		declare @T table(txtCMD nvarchar(max));
		while exists(select * from #cmdQueue)
		begin
			delete top (1) from #cmdQueue output deleted.* into @T;
			select top 1 @SQLCMD = txtCMD  from @T
			PRINT @SQLCMD
			exec(@SQLCMD)
			delete from @T
		end
	end
end
GO
print 'Execute AzureSQLMaintenance to get help' 
