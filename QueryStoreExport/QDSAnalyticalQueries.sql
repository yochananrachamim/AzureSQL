-- Draft for queries to be use to analyze the data in QDS
-- this is in addition to the queries that we have in Microsoft Docs for QDS which is mainly focused on an active QDS while this is a dump of QDS for later analysis


select top 1000 avg_dop, max_dop, min_dop,* from [dbo].[query_store_runtime_stats] rs



-- Execution trend over time
select  i.start_time, sum(rs.count_executions)
from [dbo].[query_store_runtime_stats] rs
inner join [dbo].[query_store_runtime_stats_interval] i on i.runtime_stats_interval_id = rs.runtime_stats_interval_id
where 1=1 
--and i.start_time >= '2022-03-17 11:00' and i.end_time <= '2022-03-17 18:00'
and i.start_time >= '2022-03-14 00:00' and i.end_time <= '2022-03-21 00:00'
group by i.start_time
order by i.start_time

-- avg duration over time 
select  i.start_time, avg(rs.avg_duration) avgDuration , max(max_duration) maxDuration
from [dbo].[query_store_runtime_stats] rs
inner join [dbo].[query_store_runtime_stats_interval] i on i.runtime_stats_interval_id = rs.runtime_stats_interval_id
where 1=1 
and i.start_time >= '2022-03-17 08:00' and i.end_time <= '2022-03-18 08:00'
--and i.start_time >= '2022-03-14 00:00' and i.end_time <= '2022-03-21 00:00'
group by i.start_time
order by i.start_time


-- CPU
select  i.start_time, sum(avg_rowcount)
from [dbo].[query_store_runtime_stats] rs
inner join [dbo].[query_store_runtime_stats_interval] i on i.runtime_stats_interval_id = rs.runtime_stats_interval_id
where 1=1 
--and i.start_time >= '2022-03-17 11:00' and i.end_time <= '2022-03-17 18:00'
and i.start_time >= '2022-03-10 11:00' and i.end_time <= '2022-03-27 18:00'
group by i.start_time
order by i.start_time
