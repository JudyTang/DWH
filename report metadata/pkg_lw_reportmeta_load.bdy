CREATE OR REPLACE PACKAGE BODY pkg_lw_reportmeta_load IS

  g_clob       CLOB := empty_clob;
  g_blob       BLOB;
  g_doc_size   NUMBER;
  g_mime_type  VARCHAR2(100);
  g_line_count NUMBER;
  g_start_line NUMBER;
  g_file_name  VARCHAR2(100);

  g_datasetfullname VARCHAR2(100);
  g_datasetalias    VARCHAR2(100);
  g_reporttemplate  VARCHAR2(100);

  g_file_category VARCHAR2(100) := 'REPORT METADATA TOOL';
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

  FUNCTION to_date_format(p_str VARCHAR2) RETURN DATE IS
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

    SELECT id
      INTO l_dit_file_category_id
      FROM TABLE(csc_distribution_pkg.get_dimension_items_fn('FEED PROCESSING FILE CATEGORY'))
     WHERE VALUE = g_file_category;

    SELECT id
      INTO l_dit_processing_status
      FROM TABLE(csc_distribution_pkg.get_dimension_items_fn('FEED PROCESSING STATUS'))
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

    SELECT id
      INTO l_dit_processing_status
      FROM TABLE(csc_distribution_pkg.get_dimension_items_fn('FEED PROCESSING STATUS'))
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
      FROM TABLE(csc_distribution_pkg.get_dimension_items_fn('FEED LOG CATEGORY'))
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

  PROCEDURE process_dataset IS
    --PRAGMA AUTONOMOUS_TRANSACTION;
    l_column_count NUMBER;
    l_cell_value   VARCHAR2(1000);
    l_found        BOOLEAN := FALSE;

    l_alias          VARCHAR2(100);
    l_fullname       VARCHAR2(100);
    l_contentclass   VARCHAR2(100);
    l_reportproducer VARCHAR2(100);
    l_reportsource   VARCHAR2(100);

    l_err_msg VARCHAR2(300);
    e_bad_content EXCEPTION;
    e_no_alias EXCEPTION;
    e_no_fullname EXCEPTION;
    e_no_contentclass EXCEPTION;
    e_no_reportproducer EXCEPTION;
    e_no_reportsource EXCEPTION;

  BEGIN

    FOR i IN g_start_line .. g_line_count LOOP

      IF is_blank_row(i) = FALSE THEN

        l_cell_value := get_cell_value(i, 0);

        IF l_cell_value IS NOT NULL AND l_cell_value != 'DATA_SET' THEN

          IF l_found = FALSE THEN
            NULL;
          ELSE
            EXIT;
          END IF;

        ELSIF l_cell_value IS NOT NULL AND l_cell_value = 'DATA_SET' THEN

          l_found := TRUE;

          l_column_count := get_max_column(i);

          IF l_column_count < 2 THEN
            RAISE e_bad_content;
          END IF;

          l_cell_value := get_cell_value(i, 1);

          IF (l_cell_value IS NOT NULL AND l_cell_value = 'ALIAS') THEN
            l_alias := get_cell_value(i, 2);
          ELSIF (l_cell_value IS NOT NULL AND l_cell_value = 'FULL NAME') THEN
            l_fullname := get_cell_value(i, 2);
          ELSIF (l_cell_value IS NOT NULL AND
                l_cell_value = 'CONTENT CLASS') THEN
            l_contentclass := get_cell_value(i, 2);
          ELSIF (l_cell_value IS NOT NULL AND
                l_cell_value = 'REPORT PRODUCER') THEN
            l_reportproducer := get_cell_value(i, 2);
          ELSIF (l_cell_value IS NOT NULL AND l_cell_value = 'SOURCE') THEN
            l_reportsource := get_cell_value(i, 2);

          END IF;

        END IF;

      ELSE
        IF l_found = TRUE THEN
          EXIT;
        END IF;

      END IF;

    END LOOP;

    -- check content
    IF l_alias IS NULL THEN
      RAISE e_no_alias;
    END IF;

    IF l_fullname IS NULL THEN
      RAISE e_no_fullname;
    END IF;

    IF l_contentclass IS NULL THEN
      RAISE e_no_contentclass;
    END IF;

    IF l_reportproducer IS NULL THEN
      RAISE e_no_reportproducer;
    END IF;

    IF l_reportsource IS NULL THEN
      RAISE e_no_reportsource;
    END IF;

    g_datasetfullname := l_fullname;
    g_datasetalias    := l_alias;

    -- insert dataset info into db

    csc_maintain_pkg.insert_dimension_item_proc(official_name_in => 'CONTENT CLASS',
                                                value_in         => l_contentclass);

    report_maintain_pkg.insert_data_set_proc(full_name_in       => l_fullname,
                                             alias_in           => l_alias,
                                             content_class_in   => l_contentclass,
                                             report_producer_in => l_reportproducer,
                                             report_source_in   => l_reportsource);

    --COMMIT;
  EXCEPTION
    WHEN e_bad_content THEN

      l_err_msg := 'Please check the DATA_SET rows in the file, ' ||
                    'make sure the value of ALIAS,FULL NAME,CONTENT CLASS,REPORT PRODUCER,SOURCE in column C are filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;

    WHEN e_no_alias THEN

      l_err_msg := 'Please check the DATA_SET rows in the file, ' ||
                    'make sure the value of ALIAS in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN e_no_fullname THEN

      l_err_msg := 'Please check the DATA_SET rows in the file,  ' ||
                    'make sure the value of FULL NAME in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN e_no_contentclass THEN

      l_err_msg := 'Please check the DATA_SET rows in the file,  ' ||
                    'make sure the value of CONTENT CLASS in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN e_no_reportproducer THEN

      l_err_msg := 'Please check the DATA_SET rows in the file, ' ||
                    'make sure the value of REPORT PRODUCER in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN e_no_reportsource THEN

      l_err_msg := 'Please check the DATA_SET rows in the file, ' ||
                    'make sure the value of SOURCE in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN OTHERS THEN
      --ROLLBACK;
      l_err_msg := 'Critical Error: processDataSet: ' || SQLCODE || ' - ' ||
                    substr(SQLERRM, 1, 300);

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      RAISE;
  END process_dataset;

  PROCEDURE process_report_template IS
    --PRAGMA AUTONOMOUS_TRANSACTION;
    l_column_count NUMBER;
    l_cell_value   VARCHAR2(1000);
    l_found        BOOLEAN := FALSE;

    l_rtname           VARCHAR2(100);
    l_releasefrequency VARCHAR2(100);
    l_code             VARCHAR2(100);
    l_measurement      VARCHAR2(100);

    l_err_msg VARCHAR2(300);
    e_bad_content EXCEPTION;
    e_no_rtname EXCEPTION;
    e_no_releasefrequency EXCEPTION;
    e_process_order EXCEPTION;

  BEGIN

    IF g_datasetfullname IS NOT NULL THEN

      FOR i IN g_start_line .. g_line_count LOOP

        IF is_blank_row(i) = FALSE THEN

          l_cell_value := get_cell_value(i, 0);

          IF l_cell_value IS NOT NULL AND l_cell_value != 'REPORT_TEMPLATE' THEN

            IF l_found = FALSE THEN
              NULL;
            ELSE
              EXIT;
            END IF;

          ELSIF l_cell_value IS NOT NULL AND
                l_cell_value = 'REPORT_TEMPLATE' THEN

            l_found := TRUE;

            l_column_count := get_max_column(i);

            IF l_column_count < 2 THEN
              RAISE e_bad_content;
            END IF;

            l_cell_value := get_cell_value(i, 1);

            IF (l_cell_value IS NOT NULL AND l_cell_value = 'NAME') THEN
              l_rtname := get_cell_value(i, 2);
            ELSIF (l_cell_value IS NOT NULL AND
                  l_cell_value = 'RELEASE FREQUENCY') THEN
              l_releasefrequency := get_cell_value(i, 2);
            ELSIF (l_cell_value IS NOT NULL AND l_cell_value = 'CODE') THEN
              l_code := get_cell_value(i, 2);
            ELSIF (l_cell_value IS NOT NULL AND
                  l_cell_value = 'MEASUREMENT UNIT') THEN
              l_measurement := get_cell_value(i, 2);

            END IF;

          END IF;

        ELSE
          IF l_found = TRUE THEN
            EXIT;
          END IF;

        END IF;

      END LOOP;

      -- check content
      IF l_rtname IS NULL THEN
        RAISE e_no_rtname;
      END IF;

      IF l_releasefrequency IS NULL THEN
        RAISE e_no_releasefrequency;
      END IF;

      g_reporttemplate := l_rtname;

      -- insert dataset info into db
      IF l_measurement IS NOT NULL THEN

        report_maintain_pkg.insert_measurement_proc(name_in => l_measurement);
      END IF;

      report_maintain_pkg.insert_report_template_proc(report_template_name_in => l_rtname,
                                                      report_template_code_in => l_code,
                                                      release_frequency_in    => l_releasefrequency,
                                                      measurement_in          => l_measurement,
                                                      data_set_in             => g_datasetfullname);

      --COMMIT;
    ELSE
      RAISE e_process_order;

    END IF;

  EXCEPTION
    WHEN e_bad_content THEN

      l_err_msg := 'Please check the REPORT_TEMPLATE rows in the file, ' ||
                    'make sure the value of NAME,RELEASE FREQUENCY in column C are filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;

    WHEN e_no_rtname THEN

      l_err_msg := 'Please check the REPORT_TEMPLATE rows in the file, ' ||
                    'make sure the value of NAME in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN e_no_releasefrequency THEN

      l_err_msg := 'Please check the REPORT_TEMPLATE rows in the file,  ' ||
                    'make sure the value of RELEASE FREQUENCY in column C is filled';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;
    WHEN e_process_order THEN

      l_err_msg := 'Failed when processing REPORT_TEMPLATE, DATA_SET has not been processed yet! ';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      RAISE;
    WHEN OTHERS THEN
      --ROLLBACK;
      l_err_msg := 'Critical Error: processReportTemplate: ' || SQLCODE ||
                    ' - ' || substr(SQLERRM, 1, 300);

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      RAISE;

  END process_report_template;

  PROCEDURE process_dimension_item IS
    --PRAGMA AUTONOMOUS_TRANSACTION;
    l_dim_line     NUMBER;
    l_data_line    NUMBER;
    l_cell_value   VARCHAR2(1000);
    l_column_count NUMBER;
    l_tmp          NUMBER;

    l_collectivedimension VARCHAR2(1000);
    l_basicdimension      VARCHAR2(1000);
    l_dimensionitemvalue  VARCHAR2(1000);
    l_uniquecode          VARCHAR2(1000);
    l_found               BOOLEAN := FALSE;

    l_err_msg VARCHAR2(300);
    e_bad_content EXCEPTION;
    e_process_order EXCEPTION;
    e_no_dimension EXCEPTION;

  BEGIN

    IF g_datasetalias IS NOT NULL AND g_reporttemplate IS NOT NULL THEN

      FOR i IN g_start_line .. g_line_count LOOP

        l_cell_value := get_cell_value(i, 0);

        IF l_cell_value IS NOT NULL AND l_cell_value = 'DIMENSION' THEN

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

          l_found        := TRUE;
          l_column_count := get_max_column(i);

          IF l_column_count < 1 THEN
            RAISE e_bad_content;
          END IF;

          l_collectivedimension := get_cell_value(i, 0);

          l_tmp := instr(l_collectivedimension, g_datasetalias);

          IF l_tmp > 0 THEN
            l_basicdimension := substr(l_collectivedimension,
                                       0,
                                       (l_tmp - 2));
          ELSE

            l_basicdimension := l_collectivedimension;

          END IF;

          l_dimensionitemvalue := get_cell_value(i, 1);

          IF l_column_count >= 2 THEN
            l_uniquecode := get_cell_value(i, 2);

          END IF;

          -- insert dimension and item value into db
          csc_maintain_pkg.insert_dimension_proc(official_name_in    => l_basicdimension,
                                                 management_level_in => 'APPLICATION');
          csc_maintain_pkg.insert_dimension_proc(official_name_in       => l_collectivedimension,
                                                 group_type_in          => 'COLLECTIVE DIMENSION',
                                                 base_dimension_name_in => l_basicdimension,
                                                 management_level_in    => 'SYSTEM');
          csc_maintain_pkg.insert_dimension_item_proc(official_name_in => l_basicdimension,
                                                      value_in         => l_dimensionitemvalue,
                                                      unique_code_in   => l_uniquecode);
          csc_maintain_pkg.insert_dimension_item_proc(official_name_in => l_collectivedimension,
                                                      value_in         => l_dimensionitemvalue,
                                                      unique_code_in   => l_uniquecode);
          report_maintain_pkg.insert_template_dimension_proc(dimension_name_in       => l_collectivedimension,
                                                             report_template_name_in => g_reporttemplate,
                                                             dataset_name_in         => g_datasetfullname);
          --COMMIT;

        ELSE
          IF l_found = TRUE THEN
            EXIT;
          END IF;
        END IF;

      END LOOP;

    ELSE
      RAISE e_process_order;

    END IF;

  EXCEPTION
    WHEN e_bad_content THEN

      l_err_msg := 'Bad content of DIMMENSION rows in the file, ';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;

    WHEN e_no_dimension THEN

      l_err_msg := 'Bad content, there is no DIMMENSION rows in the file, ';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'D');

      RAISE;

    WHEN e_process_order THEN

      l_err_msg := 'Failed when processing DIMENSION_ITEM, ' ||
                    'DATA_SET or REPORT_TEMPLATE has not been processed yet!';

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      RAISE;
    WHEN OTHERS THEN
      --ROLLBACK;
      l_err_msg := 'Critical Error: processDimensionItem: ' || SQLCODE ||
                    ' - ' || substr(SQLERRM, 1, 300);

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      RAISE;

  END process_dimension_item;

  PROCEDURE start_loading(p_file       IN VARCHAR2,
                          p_charset_id IN NUMBER,
                          p_fph_id_out OUT NUMBER) IS
    --PRAGMA AUTONOMOUS_TRANSACTION;
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

    process_dataset;
    process_report_template;
    process_dimension_item;

    complete_file_process(p_fph_id => g_fph_id, p_is_failed => FALSE);

  EXCEPTION
    WHEN e_file_type THEN
      l_err_msg := 'Loading Cancelled - Source file ' || g_file_name ||
                   ' has mime-type ' || g_mime_type || ',' ||
                   ' thus could not process data.';

      --DELETE FROM wwv_flow_files WHERE NAME = p_file;
      --commit; ??

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      complete_file_process(p_fph_id => g_fph_id, p_is_failed => TRUE);

    WHEN e_bad_content THEN
      l_err_msg := 'empty file - Source file ' || g_file_name;

      --DELETE FROM wwv_flow_files WHERE NAME = p_file;
      --commit; ??

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      complete_file_process(p_fph_id => g_fph_id, p_is_failed => TRUE);

    WHEN OTHERS THEN
      l_err_msg := 'Critical Error: ' || SQLCODE || ' - ' ||
                   substr(SQLERRM, 1, 300);

      --DELETE FROM wwv_flow_files WHERE NAME = p_file;
      --commit; ??

      log_details(p_fph_id           => g_fph_id,
                       p_message_category => 'ERROR',
                       p_message          => l_err_msg,
                       p_err_type         => 'E');

      complete_file_process(p_fph_id => g_fph_id, p_is_failed => TRUE);

  END start_loading;

END pkg_lw_reportmeta_load;
/
