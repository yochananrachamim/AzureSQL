# Use an official Python runtime as a parent image
FROM python:3.8-slim

# Set the working directory to /app
WORKDIR /app

# Install the SQL Server tools (sqlcmd) and ODBC drivers
RUN apt-get update \
    && apt-get install -y curl \
    && apt-get install -y gnupg \
    && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y mssql-tools \
    && apt-get install vim -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/


# Copy the current directory contents into the container at /app
COPY . /app

# Install any Python dependencies specified in requirements.txt
#RUN pip install -r requirements.txt

# Define the default command to run your Python script with sqlcmd
CMD ["python", "sql_maintenance.py"]
