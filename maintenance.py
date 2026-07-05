import os
import re
import pyodbc

from azure.identity import DefaultAzureCredential

SERVER = os.environ["MAINTENANCE_DB_CONNECTION_URL"]
DATABASE = os.environ["MAINTENANCE_DB_NAME"]

SQL_FILE = "/app/AzureSQLMaintenance.sql"


###########################################################
# Managed Identity Login
###########################################################
def get_connection():

    credential = DefaultAzureCredential()

    token = credential.get_token(
        "https://database.windows.net/.default"
    ).token.encode("utf-16-le")

    token_struct = len(token).to_bytes(4, "little") + token

    SQL_COPT_SS_ACCESS_TOKEN = 1256

    conn = pyodbc.connect(
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={SERVER};"
        f"Database={DATABASE};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;",
        attrs_before={
            SQL_COPT_SS_ACCESS_TOKEN: token_struct
        },
        autocommit=True,
    )

    return conn


###########################################################
# Consume remaining result sets
###########################################################
def consume_results(cursor):

    while True:

        try:

            while cursor.nextset():
                pass

            break

        except pyodbc.Error:

            break


###########################################################
# Execute AzureSQLMaintenance.txt
###########################################################
def execute_sql_file(cursor, path):

    print(f"Loading SQL file : {path}")

    with open(path, encoding="utf-8") as f:
        sql = f.read()

    batches = re.split(
        r"^\s*GO\s*$",
        sql,
        flags=re.MULTILINE,
    )

    batch_no = 1

    for batch in batches:

        batch = batch.strip()

        if not batch:
            continue

        print(f"Executing batch {batch_no}")

        cursor.execute(batch)

        consume_results(cursor)

        batch_no += 1

    print("Procedure deployed successfully")


###########################################################
# Execute Query
###########################################################
def execute_query(cursor, query):

    cursor.execute(query)

    consume_results(cursor)


###########################################################
# Main
###########################################################
def main():

    print("Starting Azure SQL Maintenance")

    conn = get_connection()

    cursor = conn.cursor()

    print(f"Connected to Server : {SERVER}")
    print(f"Connected to Database : {DATABASE}")

    cursor.execute("SELECT @@VERSION")

    print(cursor.fetchone()[0])

    print("\nCreating AzureSQLMaintenance Procedure")

    execute_sql_file(cursor, SQL_FILE)

    print("\nProcedure created successfully")

    ###################################################
    # Same sequence as old sqlcmd script
    ###################################################

    print("\nRunning Index Maintenance")

    execute_query(
        cursor,
        """
        EXEC AzureSQLMaintenance
            @Operation='index',
            @mode='smart',
            @LogToTable=1
        """,
    )

    print("Index Maintenance Completed")

    print("\nRunning Statistics Maintenance")

    execute_query(
        cursor,
        """
        EXEC AzureSQLMaintenance
            @Operation='statistics',
            @mode='dummy',
            @LogToTable=1
        """,
    )

    print("Statistics Maintenance Completed")

    cursor.close()

    conn.close()

    print("\nMaintenance Finished Successfully")


if __name__ == "__main__":

    try:

        main()

    except Exception as ex:

        print(f"\nMaintenance failed : {ex}")

        raise