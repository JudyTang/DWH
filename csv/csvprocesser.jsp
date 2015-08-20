create or replace and compile java source named csvprocesser as
import com.csvreader.*;
import java.sql.Clob;
import java.io.Reader;
import java.io.BufferedReader;
import java.io.IOException;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.sql.*;
import java.io.*;
import oracle.jdbc.*;
public class CSVProcesser
{
   	public static void processCSV(Clob clob) throws IOException,SQLException {

		String sql = "INSERT INTO csv_to_table_tmp(LINE_NUMBER,COLUMN_NUMBER,CELL_VALUE) VALUES (?,?,?)";

		CsvReader reader = null;
		Connection conn = null;
		List<String[]> csvList = new ArrayList<String[]>();

		try {
			Reader is = clob.getCharacterStream();
			BufferedReader br = new BufferedReader(is);
			reader = new CsvReader(br);

			while (reader.readRecord()) {
				csvList.add(reader.getValues());

			}

			reader.close();

		} catch (SQLException e) {

			throw e;

		} catch (IOException e) {
			// TODO Auto-generated catch block
			throw e;
		}

		try {
			conn = DriverManager.getConnection("jdbc:default:connection:");
			conn.setAutoCommit(false);

			PreparedStatement pstmt = conn.prepareStatement(sql);

			for (int i = 0; i < csvList.size(); i++) {

				for (int j = 0; j < csvList.get(i).length; j++) {

					String cell = (csvList.get(i)[j]).trim();

					pstmt.setInt(1, i);
					pstmt.setInt(2, j);
					pstmt.setString(3, cell);

					try {
						pstmt.executeUpdate();
					} catch (SQLException e) {

						throw e;
					}

				}

			}

			pstmt.close();

		} catch (SQLException e) {

			throw e;

		} finally {
			try {
				conn.close();
			} catch (SQLException e) {
				throw e;
			}

		}

	
	}

}
/
