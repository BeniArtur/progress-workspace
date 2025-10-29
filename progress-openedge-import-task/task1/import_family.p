/* ========================================================================
   Program:     import_family.p
   Description: Import Employee Family information from CSV file
   Author:      Name
   Date:        October 29, 2025
   Database:    sports2020
   ======================================================================== */

/* Connect to database */
/*CONNECT "C:\OpenEdgeWork\sports2020" -H localhost -S 20000 NO-ERROR.*/
/*                                                                    */
/*IF ERROR-STATUS:ERROR THEN DO:                                      */
/*    MESSAGE "Database connection error:" ERROR-STATUS:GET-MESSAGE(1)*/
/*        VIEW-AS ALERT-BOX ERROR.                                    */
/*    RETURN.                                                         */
/*END.                                                                */

DEFINE INPUT PARAMETER pcInputFile AS CHARACTER NO-UNDO.

DEFINE VARIABLE cLine      AS CHARACTER NO-UNDO.
DEFINE VARIABLE cLogFile   AS CHARACTER NO-UNDO.
DEFINE VARIABLE iLineNum   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iProcessed AS INTEGER   NO-UNDO.
DEFINE VARIABLE iUpdated   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iCreated   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iErrors    AS INTEGER   NO-UNDO.
DEFINE VARIABLE lSuccess   AS LOGICAL   NO-UNDO.
DEFINE VARIABLE cErrorMsg  AS CHARACTER NO-UNDO.
DEFINE VARIABLE iLastEmpNum AS INTEGER  NO-UNDO.


DEFINE TEMP-TABLE ttImportData NO-UNDO
    FIELD LineNum       AS INTEGER
    FIELD EmpNum        AS INTEGER
    FIELD RecordType    AS CHARACTER
    FIELD FirstName     AS CHARACTER
    FIELD LastName      AS CHARACTER
    FIELD Birthdate     AS DATE
    INDEX idxEmp EmpNum LineNum.

/* Initialize */
ASSIGN
    iLineNum   = 0
    iProcessed = 0
    iUpdated   = 0
    iCreated   = 0
    iErrors    = 0
    cLogFile   = "log/family_import.log".

/* Create log directory if not exists */
OS-CREATE-DIR "log".

/* Start logging */
RUN WriteLog("INFO", "========================================").
RUN WriteLog("INFO", "Family Import Process Started").
RUN WriteLog("INFO", "Input File: " + pcInputFile).
RUN WriteLog("INFO", "========================================").

/* Step 1: Read and parse CSV file */
RUN ReadCSVFile(pcInputFile, OUTPUT lSuccess, OUTPUT cErrorMsg).

IF NOT lSuccess THEN DO:
    RUN WriteLog("FATAL", "Failed to read CSV file: " + cErrorMsg).
    RETURN.
END.

RUN WriteLog("INFO", "CSV file loaded successfully. Lines: " + STRING(iLineNum)).

/* Step 2: Process records by Employee (ONE TRANSACTION PER EMPLOYEE) */
DEFINE VARIABLE iCurrentEmp AS INTEGER NO-UNDO.
DEFINE VARIABLE iPrevEmp    AS INTEGER NO-UNDO.
DEFINE VARIABLE iEmpRecords AS INTEGER NO-UNDO.

iPrevEmp = 0.

FOR EACH ttImportData BY ttImportData.EmpNum BY ttImportData.LineNum:
    
    iCurrentEmp = ttImportData.EmpNum.
    
    /* When Employee changes, start new transaction */
    IF iCurrentEmp <> iPrevEmp THEN DO:
        IF iPrevEmp <> 0 THEN DO:
            /* Previous employee transaction completed */
            RUN WriteLog("INFO", "Completed Employee " + STRING(iPrevEmp) + 
                        " - " + STRING(iEmpRecords) + " records").
        END.
        
        /* Start new employee transaction */
        iEmpRecords = 0.
        DO TRANSACTION:
            RUN ProcessEmployeeRecords(iCurrentEmp, OUTPUT lSuccess, OUTPUT cErrorMsg).
            
            IF NOT lSuccess THEN DO:
                iErrors = iErrors + 1.
                RUN WriteLog("ERROR", "Employee " + STRING(iCurrentEmp) + ": " + cErrorMsg).
                UNDO, LEAVE.
            END.
        END.
    END.
    
    iPrevEmp = iCurrentEmp.
END.

/* Last employee summary */
IF iPrevEmp <> 0 THEN
    RUN WriteLog("INFO", "Completed Employee " + STRING(iPrevEmp) + 
                " - " + STRING(iEmpRecords) + " records").

/* Step 3: Validate consistency */
RUN ValidateConsistency(OUTPUT lSuccess, OUTPUT cErrorMsg).

IF NOT lSuccess THEN
    RUN WriteLog("WARN", "Consistency check failed: " + cErrorMsg).
ELSE
    RUN WriteLog("INFO", "Consistency check passed").

/* Final summary */
RUN WriteLog("INFO", "========================================").
RUN WriteLog("INFO", "Import Process Completed").
RUN WriteLog("INFO", "Total Lines Processed: " + STRING(iProcessed)).
RUN WriteLog("INFO", "Records Created: " + STRING(iCreated)).
RUN WriteLog("INFO", "Records Updated: " + STRING(iUpdated)).
RUN WriteLog("INFO", "Errors: " + STRING(iErrors)).
RUN WriteLog("INFO", "========================================").

/* Disconnect */
DISCONNECT sports2020 NO-ERROR.

/* ========================================================================
   Procedure: ReadCSVFile
   Purpose:   Read and parse CSV file into temp-table
   ======================================================================== */
PROCEDURE ReadCSVFile:
    DEFINE INPUT  PARAMETER pcFile    AS CHARACTER NO-UNDO.
    DEFINE OUTPUT PARAMETER plSuccess AS LOGICAL   NO-UNDO.
    DEFINE OUTPUT PARAMETER pcError   AS CHARACTER NO-UNDO.
    
    DEFINE VARIABLE cFields     AS CHARACTER NO-UNDO EXTENT 5.
    DEFINE VARIABLE cLine       AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iLastEmpNum AS INTEGER NO-UNDO.
    DEFINE VARIABLE i           AS INTEGER NO-UNDO.
    DEFINE VARIABLE iLocalLine  AS INTEGER NO-UNDO.
    
    plSuccess = TRUE.
    iLastEmpNum = 0.
    iLocalLine = 0.
    
    FILE-INFO:FILE-NAME = pcFile.
    IF FILE-INFO:FULL-PATHNAME = ? THEN DO:
        ASSIGN 
            plSuccess = FALSE
            pcError   = "File not found: " + pcFile.
        RETURN.
    END.
    
    INPUT FROM VALUE(pcFile).
    IMPORT UNFORMATTED cLine. /* skip header */
    
    REPEAT:
        IMPORT DELIMITER ";" cFields NO-ERROR.
        
        IF ERROR-STATUS:ERROR THEN LEAVE.
        
        /* Remove quotes from all fields */
        DO i = 1 TO 5:
            IF cFields[i] <> ? THEN
                cFields[i] = REPLACE(cFields[i], '"', '').
        END.
        
        /* Check for end of data */
        IF cFields[1] = "Total Employees" THEN LEAVE.
        
        /* Skip empty lines */
        IF cFields[1] = ? AND cFields[2] = ? THEN NEXT.
        
        iLocalLine = iLocalLine + 1.
        
        CREATE ttImportData.
        ASSIGN
            ttImportData.LineNum    = iLocalLine
            ttImportData.RecordType = TRIM(cFields[2])
            ttImportData.FirstName  = TRIM(cFields[3])
            ttImportData.LastName   = TRIM(cFields[4]).
        
        /* Handle EmpNum - if empty, use last employee number */
        IF cFields[1] <> "" AND cFields[1] <> ? THEN DO:
            ASSIGN ttImportData.EmpNum = INTEGER(cFields[1]) NO-ERROR.
            IF NOT ERROR-STATUS:ERROR THEN
                iLastEmpNum = ttImportData.EmpNum.
            ELSE DO:
                DELETE ttImportData.
                iLocalLine = iLocalLine - 1.
                NEXT.
            END.
        END.
        ELSE DO:
            /* Empty EmpNum means family member of last employee */
            IF iLastEmpNum = 0 THEN DO:
                DELETE ttImportData.
                iLocalLine = iLocalLine - 1.
                NEXT.
            END.
            ttImportData.EmpNum = iLastEmpNum.
        END.
        
        /* Convert birthdate */
        ASSIGN ttImportData.Birthdate = DATE(cFields[5]) NO-ERROR.
        IF ERROR-STATUS:ERROR THEN ttImportData.Birthdate = ?.
    END.
    
    INPUT CLOSE.
    
    /* Update global line counter */
    iLineNum = iLocalLine.
    
    CATCH eError AS Progress.Lang.Error:
        ASSIGN 
            plSuccess = FALSE
            pcError   = eError:GetMessage(1).
        INPUT CLOSE.
    END CATCH.
END PROCEDURE.

/* ========================================================================
   Procedure: ProcessEmployeeRecords
   Purpose:   Process all Family records for ONE Employee in ONE transaction
   ======================================================================== */
PROCEDURE ProcessEmployeeRecords:
    DEFINE INPUT  PARAMETER piEmpNum  AS INTEGER   NO-UNDO.
    DEFINE OUTPUT PARAMETER plSuccess AS LOGICAL   NO-UNDO.
    DEFINE OUTPUT PARAMETER pcError   AS CHARACTER NO-UNDO.
    
    DEFINE BUFFER bEmployee FOR Employee.
    DEFINE BUFFER bFamily   FOR Family.
    DEFINE BUFFER bImport   FOR ttImportData.
    
    plSuccess = TRUE.
    
    /* Validate Employee exists */
    FIND FIRST bEmployee NO-LOCK
        WHERE bEmployee.EmpNum = piEmpNum NO-ERROR.
    
    IF NOT AVAILABLE bEmployee THEN DO:
        ASSIGN 
            plSuccess = FALSE
            pcError   = "Employee " + STRING(piEmpNum) + " not found".
        RETURN.
    END.
    
    /* Process all Family records for this Employee */
    FOR EACH bImport WHERE bImport.EmpNum = piEmpNum:
        
        /* Skip Employee records */
        IF bImport.RecordType = "Employee" THEN DO:
            RUN WriteLog("TRACE", "Line " + STRING(bImport.LineNum) + 
                        ": Skipping Employee record").
            NEXT.
        END.
        
        /* Validate required fields */
        IF bImport.LastName = "" OR bImport.LastName = ? THEN DO:
            RUN WriteLog("ERROR", "Line " + STRING(bImport.LineNum) + 
                        ": LastName is required").
            iErrors = iErrors + 1.
            NEXT.
        END.
        
        /* Find or create Family record - using LastName as RelativeName */
        FIND FIRST bFamily EXCLUSIVE-LOCK
            WHERE bFamily.EmpNum = piEmpNum
            AND   bFamily.RelativeName = bImport.LastName NO-ERROR.
        
        IF AVAILABLE bFamily THEN DO:
            /* UPDATE existing record */
            ASSIGN
                bFamily.Relation    = bImport.RecordType
                bFamily.Birthdate   = bImport.Birthdate.
            
            iUpdated = iUpdated + 1.
            RUN WriteLog("INFO", "Line " + STRING(bImport.LineNum) + 
                        ": Updated Family for Emp " + STRING(piEmpNum) + 
                        ", Rel: " + bImport.LastName).
        END.
        ELSE DO:
            /* CREATE new record */
            CREATE bFamily.
            ASSIGN
                bFamily.EmpNum       = piEmpNum
                bFamily.RelativeName = bImport.LastName
                bFamily.Relation     = bImport.RecordType
                bFamily.Birthdate    = bImport.Birthdate.
            
            iCreated = iCreated + 1.
            RUN WriteLog("INFO", "Line " + STRING(bImport.LineNum) + 
                        ": Created Family for Emp " + STRING(piEmpNum) + 
                        ", Rel: " + bImport.LastName).
        END.
        
        iProcessed = iProcessed + 1.
    END.
    
    CATCH eError AS Progress.Lang.Error:
        ASSIGN 
            plSuccess = FALSE
            pcError   = eError:GetMessage(1).
    END CATCH.
END PROCEDURE.

/* ========================================================================
   Procedure: ValidateConsistency
   Purpose:   Validate Total Employees vs Total Family Members
   ======================================================================== */
PROCEDURE ValidateConsistency:
    DEFINE OUTPUT PARAMETER plSuccess AS LOGICAL   NO-UNDO.
    DEFINE OUTPUT PARAMETER pcError   AS CHARACTER NO-UNDO.
    
    DEFINE VARIABLE iCSVEmployees AS INTEGER NO-UNDO.
    DEFINE VARIABLE iCSVFamily    AS INTEGER NO-UNDO.
    DEFINE VARIABLE iDBEmployees  AS INTEGER NO-UNDO.
    DEFINE VARIABLE iDBFamily     AS INTEGER NO-UNDO.
    
    plSuccess = TRUE.
    
    /* Count from CSV */
    FOR EACH ttImportData WHERE ttImportData.RecordType = "Employee":
        iCSVEmployees = iCSVEmployees + 1.
    END.
    
    FOR EACH ttImportData WHERE ttImportData.RecordType <> "Employee":
        iCSVFamily = iCSVFamily + 1.
    END.
    
    /* Count from Database */
    FOR EACH Employee NO-LOCK:
        iDBEmployees = iDBEmployees + 1.
    END.
    
    FOR EACH Family NO-LOCK:
        iDBFamily = iDBFamily + 1.
    END.
    
    RUN WriteLog("INFO", "CSV Employees: " + STRING(iCSVEmployees)).
    RUN WriteLog("INFO", "CSV Family Members: " + STRING(iCSVFamily)).
    RUN WriteLog("INFO", "DB Employees: " + STRING(iDBEmployees)).
    RUN WriteLog("INFO", "DB Family Members: " + STRING(iDBFamily)).
    
    /* Validate consistency */
    IF iCSVFamily <> (iCreated + iUpdated) THEN DO:
        ASSIGN 
            plSuccess = FALSE
            pcError   = "Mismatch: CSV Family (" + STRING(iCSVFamily) + 
                       ") vs Processed (" + STRING(iCreated + iUpdated) + ")".
    END.
END PROCEDURE.

/* ========================================================================
   Procedure: WriteLog
   Purpose:   Write log entry with timestamp and level to FILE
   ======================================================================== */
PROCEDURE WriteLog:
    DEFINE INPUT PARAMETER pcLevel   AS CHARACTER NO-UNDO.
    DEFINE INPUT PARAMETER pcMessage AS CHARACTER NO-UNDO.
    
    DEFINE VARIABLE cTimestamp AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cLogEntry  AS CHARACTER NO-UNDO.
    
    /* Format timestamp in ISO-8601 with milliseconds */
    cTimestamp = STRING(TODAY, "9999-99-99") + "T" + 
                 STRING(TIME, "HH:MM:SS") + "." + 
                 STRING(MTIME MOD 1000, "999").
    
    cLogEntry = cTimestamp + " [" + pcLevel + "] " + pcMessage.
    
    /* Write to log file */
    OUTPUT TO VALUE(cLogFile) APPEND.
    PUT UNFORMATTED cLogEntry SKIP.
    OUTPUT CLOSE.
    
    /* Also display on console for debugging */
    DISPLAY cLogEntry WITH FRAME frmLog DOWN WIDTH 180 NO-LABELS.
END PROCEDURE.