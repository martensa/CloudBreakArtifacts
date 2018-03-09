-- Cleanup HDFS directory
rmf /user/root/retail/retailsalesclean
rmf /user/root/retail/georevenue

-- Loading raw data
InputFile = LOAD '/user/root/retail/retailsalesraw/OnlineRetail.txt' using PigStorage('\t') 
				 as (	InvoiceNo: int,
                 			StockCode: chararray,
                        		Description: chararray,
                	 		Quantity: int,
                        		InvoiceDate: chararray,
                        		UnitPrice: float,
                        		CustomerID: int,
                        		Country: chararray);
-- Cleansing File                        
RetailSalesRaw = filter InputFile BY NOT (InvoiceDate matches 'InvoiceDate');
RetailSalesClean = FOREACH RetailSalesRaw GENERATE 	InvoiceNo,
							StockCode,
                                                    	Description,
                                                    	Quantity,                                                
                                                    	CONCAT(InvoiceDate,':00') as (InvoiceDate:chararray),
                                                    	UnitPrice,
                                                    	ROUND(UnitPrice * Quantity * 100f)/100f as (TotalPrice: float),
                                                    	CustomerID,
                                                    	Country;
-- Storing Cleansed File                                                    
STORE RetailSalesClean into '/user/root/retail/retailsalesclean' using PigStorage ('\t');

-- Generate Overall Sales Aggregate and Sales for top 10 countries
GeoGroup = group RetailSalesClean by Country;
GeoRevenue  = foreach GeoGroup generate group, ROUND(SUM(RetailSalesClean.TotalPrice)) as TotalRevenueByCountry;
GeoRevenueDesc = ORDER GeoRevenue BY TotalRevenueByCountry DESC;
Top10GeoRevenue = LIMIT GeoRevenueDesc 10;

STORE Top10GeoRevenue into '/user/root/retail/georevenue' using PigStorage ('\t');
