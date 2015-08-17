create or replace and compile java source named excelprocesser as
import java.io.IOException; 
import org.apache.poi.xssf.usermodel.XSSFRow;
import org.apache.poi.xssf.usermodel.XSSFSheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
public class ExcelProcesser
{
   
  public static String processExcel(String strPath)
  {
    String s = "empty";
   try
		  {
			   XSSFWorkbook xwb = new XSSFWorkbook(strPath);

	   XSSFSheet sheet = xwb.getSheetAt(0);

	   XSSFRow row;
	   String cell;
	   
	   
	
	   for (int i = sheet.getFirstRowNum(); i < sheet.getPhysicalNumberOfRows(); i++)
	   {
	    row = sheet.getRow(i);
	    for (int j = row.getFirstCellNum(); j < row.getPhysicalNumberOfCells(); j++)
	    {

	     cell = row.getCell(j).toString();
	     
	      s = s + cell + ",";
	    }
	   }
		  }
		  catch (Exception e)
		  {
		    e.printStackTrace();
		  }
      
      System.out.println(s);
      
      return s;
  
  
  }
    

}
/
