#!/bin/bash
yum install -y git
git clone https://github.com/hortonworks/SE-demo.git
cd SE-demo/Retail/RetailAnalytics
unzip OnlineRetail.txt.zip
cp OnlineRetail.txt /tmp/
sudo -u hdfs hadoop fs -mkdir /user/root
sudo -u hdfs hadoop fs -mkdir /user/root/retail
sudo -u hdfs hadoop fs -mkdir /user/root/retail/retailsalesraw
sudo -u hdfs hadoop fs -chown -R root /user/root
sudo -u hdfs hadoop fs -put /tmp/OnlineRetail.txt /user/root/retail/retailsalesraw
pig RetailSalesIngestion.pig
pig MBADataPrep.pig
cp RetailSalesRaw.ddl RetailSalesRaw.sql
cp RetailSales.ddl RetailSales.sql
hive -f RetailSalesRaw.sql
hive -f RetailSales.sql