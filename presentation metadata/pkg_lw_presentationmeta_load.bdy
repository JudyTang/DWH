CREATE OR REPLACE PACKAGE BODY pkg_lw_presentationmeta_load IS

  g_clob       CLOB := empty_clob;
  g_blob       BLOB;
  g_doc_size   NUMBER;
  g_mime_type  VARCHAR2(100);
  g_line_count NUMBER;
  g_start_line NUMBER;
  g_file_name  VARCHAR2(100);

  g_dataSetFullName VARCHAR2(100);
  g_reportID        VARCHAR2(100);

  g_file_category VARCHAR2(100) := 'PRESENTATION METADATA TOOL';
  g_fph_id        NUMBER;
  g_date_format   VARCHAR2(10) := 'YYYYMMDD';

  /* Select BLOB_CONTENT, DOC_SIZE und MIME_TYPE of loaded text/csv file */
  PROCEDURE load(p_file IN VARCHAR2, p_charset_id IN NUMBER) IS
    l_clob_offset  INTEGER := 1;
    l_blob_offset  INTEGER := 1;
    l_lang_context NUMBER := dbms_lob.default_lang_ctx;
    l_warning      INTEGER;
  BEGIN
    SELECT blob_content, doc_size, mime_type, filename
      INTO g_blob, g_doc_size, g_mime_type, g_file_name
      FROM wwv_flow_files --where id=(select max(id) from wwv_flow_files);
     WHERE NAME = p_file;
    dbms_lob.createtemporary(g_clob, TRUE);

    dbms_lob.converttoclob(g_clob,
                           g_blob,
                           g_doc_size,
                           l_clob_offset,
                           l_blob_offset,
                           p_charset_id,
                           l_lang_context,
                           l_warning);
  END load;

  FUNCTION to_date_format(p_str IN VARCHAR2) RETURN DATE IS
  BEGIN
    RETURN to_date(substr(TRIM(p_str), 1, length(g_date_format)),
                   g_date_format);
  END to_date_format;

  FUNCTION get_cell_value(p_line_number   IN NUMBER,
                             p_column_number IN NUMBER) RETURN VARCHAR2 IS

    l_cell_value VARCHAR2(1000);
  BEGIN

    SELECT TRIM(cell_value)
      INTO l_cell_value
      FROM csv_to_table_tmp
     WHERE line_number = p_line_number
       AND column_number = p_column_number;

    RETURN l_cell_value;

  END get_cell_value;

  FUNCTION get_max_column(p_line_number IN NUMBER) RETURN NUMBER IS

    l_max_column NUMBER;
  BEGIN

    SELECT MAX(column_number)
      INTO l_max_column
      FROM csv_to_table_tmp
     WHERE line_number = p_line_number;

    RETURN l_max_column;

  END get_max_column;

  FUNCTION get_min_column(p_line_number IN NUMBER) RETURN NUMBER IS

    l_min_column NUMBER;
  BEGIN

    SELECT MIN(column_number)
      INTO l_min_column
      FROM csv_to_table_tmp
     WHERE line_number = p_line_number;

    RETURN l_min_column;

  END get_min_column;

  FUNCTION is_blank_row(p_line_number IN NUMBER) RETURN BOOLEAN IS

    l_blank      BOOLEAN := TRUE;
    l_max_column NUMBER;
    l_min_column NUMBER;
    l_cell_value VARCHAR2(1000);
  BEGIN

    l_max_column := get_max_column(p_line_number);
    l_min_column := get_min_column(p_line_number);

    FOR i IN l_min_column .. l_max_column LOOP

      l_cell_value := get_cell_value(p_line_number, i);

      IF l_cell_value IS NOT NULL THEN

        l_blank := FALSE;
        EXIT;

      END IF;

    END LOOP;

    RETURN l_blank;

  END is_blank_row;

  FUNCTION insert_file_process_his(p_file_name IN file_process_history.file_name%TYPE)
    RETURN NUMBER IS
    --PRAGMA AUTONOMOUS_TRANSACTION;
    l_dit_file_category_id  file_process_history.dit_file_category_id%TYPE;
    l_dit_processing_status file_process_history.dit_processing_status%TYPE;
    l_fph_id                file_process_history.id%TYPE;

  BEGIN

    SELECT ID
      INTO l_dit_file_category_id
      FROM TABLE(csc_distribution_pkg.get_dimension_items_fn('FEED PROCESSING FILE CATEGORY'))
     WHERE VALUE = g_file_category;

    SELECT ID
      INTO l_dit_processing_status
      FROM TABLE(CSC_DISTRIBUTION_PKG.get_dimension_items_fn('FEED PROCESSING STATUS'))
     WHERE VALUE = 'PROCESSING';

    INSERT INTO file_process_history
      (id,
       file_name,
       dit_file_category_id,
       start_time,
       dit_processing_status)
    VALUES
      (fph_seq.NEXTVAL,
       p_file_name,
       l_dit_file_category_id,
       SYSDATE,
       l_dit_processing_status)
    RETURNING id INTO l_fph_id;

    --COMMIT;

    RETURN l_fph_id;

  END insert_file_process_his;

  PROCEDURE complete_file_process(p_fph_id    IN NUMBER,
                                       p_is_failed IN BOOLEAN) IS
    --PRAGMA AUTONOMOUS_TRANSACTION;

    l_pde_count             NUMBER;
    l_processing_status     VARCHAR2(30);
    l_dit_processing_status file_process_history.dit_processing_status%TYPE;

  BEGIN

    IF p_is_failed THEN
      l_processing_status := 'FAILED';

    ELSE
      SELECT COUNT(*)
        INTO l_pde_count
        FROM processing_detail
       WHERE fph_id = p_fph_id
         AND dit_message_category_id IN
             (SELECT id FROM dimension_item WHERE VALUE = 'WARNING');

      IF l_pde_count > 0 THEN
        l_processing_status := 'COMPLETEDWITHWARNING';
      ELSE
        l_processing_status := 'COMPLETED';
      END IF;

    END IF;

    SELECT ID
      INTO l_dit_processing_status
      FROM TABLE(CSC_DISTRIBUTION_PKG.get_dimension_items_fn('FEED PROCESSING STATUS'))
     WHERE VALUE = l_processing_status;

    UPDATE file_process_history
       SET end_time              = SYSDATE,
           dit_processing_status = l_dit_processing_status
     WHERE id = p_fph_id;

    --COMMIT;

  END complete_file_process;

  PROCEDURE log_details(p_fph_id           IN NUMBER,
                             p_message_category IN VARCHAR2,
                             p_message          IN VARCHAR2,
                             p_err_type         IN VARCHAR2) IS
    l_log_message             processing_detail.message%TYPE;
    l_dit_message_category_id processing_detail.dit_message_category_id%TYPE;

  BEGIN

    l_log_message := p_message;

    IF length(p_message) > 2000 THEN

      l_log_message := substr(p_message, 0, 2000);

    END IF;

    SELECT id
      INTO l_dit_message_category_id
      FROM TABLE(CSC_DISTRIBUTION_PKG.get_dimension_items_fn('FEED LOG CATEGORY'))
     WHERE VALUE = p_message_category;

    INSERT INTO processing_detail
      (fph_id, log_time, dit_message_category_id, message, err_type)
    VALUES
      (p_fph_id,
       SYSDATE,
       l_dit_message_category_id,
       l_log_message,
       p_err_type);

    --COMMIT;

  END log_details;

  PROCEDURE process_template IS
    --PRAGMA AUTONOMOUS_TRANSACTION;
    l_column_count NUMBER;
    l_cell_value   VARCHAR2(1000);
    l_found        BOOLEAN := FALSE;
    l_pte_id       presentation_template.id%TYPE;

    l_reportID        VARCHAR2(100);
    l_dataSetFullName VARCHAR2(100);

    l_err_msg VARCHAR2(300);
    e_bad_content EXCEPTION;
    e_no_reportID EXCEPTION;
    e_no_dataSetFullName EXCEPTION;

  BEGIN

    FOR i IN g_start_line .. g_line_count LOOP

      IF is_blank_row(i) = FALSE THEN

        l_cell_value := get_cell_value(i, 0);

        IF l_cell_value IS NOT NULL AND
           l_cell_value != 'PRESENTATION TEMPLATE' THEN

          IF l_found = FALSE THEN
            NULL;
          ELSE
            EXIT;
          END IF;

        ELSIF l_cell_value IS NOT NULL AND
              l_cell_value = 'PRESENTATION TEMPLATE' THEN

          l_found := TRUE;

          l_column_count := get_max_column(i);

          IF l_column_count < 2 THEN
            RAISE e_bad_content;
          END IF;

          l_cell_value := get_cell_value(i, 1);

          IF (l_cell_value IS NOT NULL AND l_cell_value = 'REPORT ID') THEN
            l_reportID := get_cell_value(i, 2);
          ELSIF (l_cell_value IS NOT NULL AND
                l_cell_value = 'DATA SET NAME') THEN
            l_dataSetFullName := get_cell_value(i, 2);

          END IF;

        END IF;

      ELSE
        IF l_found = TRUE THEN
          EXIT;
        END IF;

      END IF;

    END LOOP;

    -- check content
    IF l_reportID IS NULL THEN
      RAISE e_no_reportID;
    END IF;

    IF l_dataSetFullName IS NULL THEN
      RAISE e_no_dataSetFullName;
    END IF;

    g_dataSetFullName := l_dataSetFullName;
    g_reportID        := l_reportID;

    l_pte_id := presentation_template_pkg.insert_template_fn(name_in          => l_reportID,
                                                             data_set_name_in => l_dataSetFullName);
    --COMMIT;
  EXCEPTION
    WHEN e_bad_content THEN

      l_err_msg := 'Please check the PRESENTATION TEMPLATE rows in the file, ' ||
                    'make sure the value of REPORT ID,DATA SET NAME  in column C are filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN e_no_reportID THEN

      l_err_msg := 'Please check the PRESENTATION TEMPLATE rows in the file, ' ||
                    'make sure the value of REPORT ID in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;

    WHEN e_no_dataSetFullName THEN

      l_err_msg := 'Please check the PRESENTATION TEMPLATE rows in the file, ' ||
                    'make sure the value of  DATA SET NAME  in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN OTHERS THEN
      --ROLLBACK;
      l_err_msg := 'Critical Error: processTemplate: ' || SQLCODE || ' - ' ||
                    SUBSTR(SQLERRM, 1, 300);

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      RAISE;
  END process_template;

  PROCEDURE process_data_item IS
    --PRAGMA AUTONOMOUS_TRANSACTION;
    l_dim_line     NUMBER;
    l_data_line    NUMBER;
    l_cell_value   VARCHAR2(1000);
    l_column_count NUMBER;
    l_found        BOOLEAN := FALSE;

    l_businessId    VARCHAR2(1000);
    l_reportName    VARCHAR2(1000);
    l_cellShortName VARCHAR2(1000);

    l_err_msg VARCHAR2(300);
    e_bad_content EXCEPTION;
    e_no_dimension EXCEPTION;

  BEGIN

    FOR i IN g_start_line .. g_line_count LOOP

      l_cell_value := get_cell_value(i, 0);

      IF l_cell_value IS NOT NULL AND l_cell_value = 'BUSINESS ID' THEN

        l_dim_line := i;
        EXIT;
      END IF;
    END LOOP;

    IF l_dim_line IS NULL THEN
      RAISE e_no_dimension;

    END IF;

    l_data_line := l_dim_line + 1;

    FOR i IN l_data_line .. g_line_count LOOP
      IF is_blank_row(i) = FALSE THEN

        l_found := TRUE;

        BEGIN

          l_column_count := get_max_column(i);

          IF l_column_count < 2 THEN
            RAISE e_bad_content;
          END IF;

          l_businessId    := get_cell_value(i, 0);
          l_reportName    := get_cell_value(i, 1);
          l_cellShortName := get_cell_value(i, 2);

          -- insert data into db

          presentation_template_pkg.insert_data_item_proc(template_name_in   => g_reportID,
                                                          businessid_in      => l_businessId,
                                                          data_set_name_in   => g_dataSetFullName,
                                                          report_name_in     => l_reportName,
                                                          cell_short_name_in => l_cellShortName);

        EXCEPTION

          WHEN e_bad_content THEN
            l_err_msg := 'Bad content of DATA ITEM rows in the file, row_number = ' || i;

            log_details(p_fph_id           => g_fph_id,
                             p_message_category => 'WARNING',
                             p_message          => l_err_msg,
                             p_err_type         => 'D');

          WHEN OTHERS THEN
            IF SQLCODE = -20035 THEN

              l_err_msg := 'Data Issue: processDataItem: ' || SQLCODE ||
                            ' - ' || SUBSTR(SQLERRM, 1, 300);

              log_details(p_fph_id           => g_fph_id,
                               p_message_category => 'WARNING',
                               p_message          => l_err_msg,
                               p_err_type         => 'D');

            ELSE

              l_err_msg := 'Critical Error: processDataItem: ' || SQLCODE ||
                            ' - ' || SUBSTR(SQLERRM, 1, 300);

              log_details(p_fph_id           => g_fph_id,
                               p_message_category => 'ERROR',
                               p_message          => l_err_msg,
                               p_err_type         => 'E');

              RAISE;

            END IF;

        END;

      ELSE
        IF l_found = TRUE THEN
          EXIT;
        END IF;
      END IF;

    END LOOP;

    --COMMIT;

  EXCEPTION
    WHEN e_no_dimension THEN

      l_err_msg := 'Bad content, there is no DATA ITEM rows in the file, ';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;

    WHEN OTHERS THEN
      --ROLLBACK;
      l_err_msg := 'Critical Error: processDataItem: ' || SQLCODE || ' - ' ||
                    SUBSTR(SQLERRM, 1, 300);

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      RAISE;

  END process_data_item;

  PROCEDURE start_loading(p_file       IN VARCHAR2,
                          p_charset_id IN NUMBER,
                          p_fph_id_out OUT NUMBER) IS

    l_err_msg VARCHAR2(1000);

    e_file_type EXCEPTION;
    e_bad_content EXCEPTION;
  BEGIN
    wwv_flow_api.set_security_group_id(6422726154786658);

    load(p_file, p_charset_id);

    g_fph_id     := insert_file_process_his(g_file_name);
    p_fph_id_out := g_fph_id;

    IF g_mime_type NOT IN
       ('text/csv', 'application/text', 'text/plain', 'application/csv',
        'application/octet-stream', 'application/vnd.ms-excel') THEN
      RAISE e_file_type;
    END IF;

    -- load csv into temporary table csv_to_table_tmp
    csv_to_table(g_clob);

    SELECT nvl(MAX(line_number), -1) INTO g_line_count FROM csv_to_table_tmp;

    IF g_line_count = -1 THEN
      RAISE e_bad_content;
    END IF;

    SELECT MIN(line_number) INTO g_start_line FROM csv_to_table_tmp;

    process_template;
    process_data_item;

    complete_file_process(p_fph_id => g_fph_id, p_is_failed => FALSE);

  EXCEPTION
    WHEN e_file_type THEN
      l_err_msg := 'Loading Cancelled - Source file ' || g_file_name ||
                   ' has mime-type ' || g_mime_type || ',' ||
                   ' thus could not process data.';

      --DELETE FROM wwv_flow_files WHERE NAME = p_file;
      --commit;??

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      complete_file_process(p_fph_id => g_fph_id, p_is_failed => TRUE);

    WHEN e_bad_content THEN
      l_err_msg := 'Bad file content - Source file ' || g_file_name;

      --DELETE FROM wwv_flow_files WHERE NAME = p_file;
      --commit;??
      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      complete_file_process(p_fph_id => g_fph_id, p_is_failed => TRUE);
    WHEN OTHERS THEN
      l_err_msg := 'Critical Error: ' || SQLCODE || ' - ' ||
                   SUBSTR(SQLERRM, 1, 300);

      --DELETE FROM wwv_flow_files WHERE NAME = p_file;
      --commit;??
      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      complete_file_process(p_fph_id => g_fph_id, p_is_failed => TRUE);

  END start_loading;

END pkg_lw_presentationmeta_load;
/
