1. command line

loadjava -u cef_cnr/cef_cnr -force -resolve junit3.8.1.jar

loadjava -u cef_cnr/cef_cnr -force -resolve -genmissing log4j-1.2.13.jar

loadjava -u cef_cnr/cef_cnr -force -resolve -genmissing commons-logging-1.1.jar 

loadjava -u cef_cnr/cef_cnr -force -resolve geronimo-stax-api_1.0_spec-1.0.jar 

loadjava -u cef_cnr/cef_cnr -force -resolve -genmissing xmlbeans-2.3.0.jar

loadjava -u cef_cnr/cef_cnr -force -resolve -genmissing dom4j-1.6.1.jar

loadjava -u cef_cnr/cef_cnr -force -resolve poi-3.7-20101029.jar 

loadjava -u cef_cnr/cef_cnr -force -resolve poi-scratchpad-3.7-20101029.jar 

loadjava -u cef_cnr/cef_cnr -force -resolve -genmissing poi-ooxml-schemas-3.7-20101029.jar 

loadjava -u cef_cnr/cef_cnr -force -resolve poi-ooxml-3.7-20101029.jar 


2. excelprocesser.jsp

3. process_excel.fnc

4. 
sqlplus / as sysdba
GRANT JAVAUSERPRIV TO CEF_CNR;

exec dbms_java.grant_permission('CEF_CNR','SYS:java.io.FilePermission','/home/oracle/judy/java/test.xlsx','read');

exec dbms_java.grant_permission('CEF_CNR','SYS:java.lang.RuntimePermission','getClassLoader', '' );


