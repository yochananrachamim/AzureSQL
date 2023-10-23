import os
import subprocess

# Define your SQL Server connection details
server = os.environ['DB_CONNECTION_URL']
database = os.environ['my_db_list']
username = os.environ['DB_USERNAME']
password = os.environ['DB_PASSWORD']

sql_script = "/app/query.sql"

#converting in to absolute path
sql_script = os.path.abspath(sql_script)

query_to_run = ["exec [dbo].[AzureSQLMaintenance] @Operation='index',@mode='smart',@LogToTable=1", "exec [dbo].[AzureSQLMaintenance] @Operation='statistics',@mode='dummy' ,@LogToTable=1"]


# Creating procedure in DB
creating_procedure_command = [
    "/opt/mssql-tools/bin/sqlcmd",
    "-S", server,
    "-d", database,
    "-U", username,
    "-P", password,
    "-i", sql_script,
    "-t", "65534",
    "-l", "60"
]

#creatating procedure in DB

try:
    procedure_creation = subprocess.run(creating_procedure_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    if procedure_creation.returncode == 0:
        print("Procedure has been created successfully")
    else:
        print("Error Occured:")
        print(procedure_creation.stderr)
except subprocess.CalledProcessError as e:
    print("Error running sqlcmd command:")
    print(e.stderr)

# Triggering Procedure
for item in query_to_run:
   triggering_procedure_command =  [
    "/opt/mssql-tools/bin/sqlcmd",
    "-S", server,
    "-d", database,
    "-U", username,
    "-P", password,
    "-Q", item,
    "-t", "65534",
    "-l", "60"
   ]

   try:
       procedure_exec_index = subprocess.run(triggering_procedure_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

       if procedure_exec_index.returncode == 0:
           print("Query has been executed successfully")
       else:
           print("Error Occured:")
           print(procedure_exec_index.stderr)
   except subprocess.CalledProcessError as e:
       print("Error running sqlcmd command:")



