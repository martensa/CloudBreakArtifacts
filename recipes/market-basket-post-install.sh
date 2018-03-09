#!/bin/bash
unzip /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/OnlineRetail.txt.zip
cp OnlineRetail.txt /tmp/
sudo -u hdfs hadoop fs -mkdir /user/root
sudo -u hdfs hadoop fs -mkdir /user/root/retail
sudo -u hdfs hadoop fs -mkdir /user/root/retail/retailsalesraw
sudo -u hdfs hadoop fs -chown -R root /user/root
sudo -u hdfs hadoop fs -put /tmp/OnlineRetail.txt /user/root/retail/retailsalesraw
pig /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/RetailSalesIngestion.pig
pig /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/MBADataPrep.pig
cp /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/RetailSalesRaw.ddl /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/RetailSalesRaw.sql
cp /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/RetailSales.ddl /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/RetailSales.sql
hive -f /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/RetailSalesRaw.sql
hive -f /root/CloudBreakArtifacts/recipes/MARKET_BASKET_DEMO_CONTROL/demofiles/RetailSales.sql
