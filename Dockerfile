FROM python:3.12-bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV ACCEPT_EULA=Y

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        gnupg2 \
        ca-certificates \
        gcc \
        g++ \
        unixodbc \
        unixodbc-dev && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
        > /etc/apt/sources.list.d/microsoft-prod.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y msodbcsql18 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY maintenancefile.py .
COPY AzureSQLMaintenance.sql .

CMD ["python","maintenance.py"]