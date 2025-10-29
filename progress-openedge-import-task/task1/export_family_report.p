/* ========================================================================
   Program:     export_family_report.p
   Description: Export Employee and Family information to CSV report
   Author:       Name
   Date:        October 29, 2025
   Database:    sports2020
   ======================================================================== */


DEFINE VARIABLE cReportFile   AS CHARACTER NO-UNDO.
DEFINE VARIABLE cReportDate   AS CHARACTER NO-UNDO.
DEFINE VARIABLE cReportTime   AS CHARACTER NO-UNDO.
DEFINE VARIABLE iEmpCount     AS INTEGER   NO-UNDO.
DEFINE VARIABLE iFamilyCount  AS INTEGER   NO-UNDO.
DEFINE VARIABLE dCutoffDate   AS DATE      NO-UNDO.


dCutoffDate = TODAY - (40 * 365).

ASSIGN
    cReportDate = STRING(YEAR(TODAY), "9999") + 
                  STRING(MONTH(TODAY), "99") + 
                  STRING(DAY(TODAY), "99")
    cReportTime = REPLACE(STRING(TIME, "HH:MM:SS"), ":", "")
    cReportFile = "report/EmployeesReport_" + cReportDate + "_" + cReportTime + ".csv".

/* Create report directory if not exists */
OS-CREATE-DIR "report".

/* Generate the report */
OUTPUT TO VALUE(cReportFile).

/* Write header line */
PUT UNFORMATTED 
    '"EmpNum";"Type";"First Name";"Last Name";"Birth Date"' SKIP.

/* Process Employees and their Families */
FOR EACH Employee NO-LOCK
    WHERE Employee.Birthdate >= dCutoffDate
    BY Employee.Birthdate:
    
    /* Check if Employee has Family members */
    FIND FIRST Family NO-LOCK
        WHERE Family.EmpNum = Employee.EmpNum NO-ERROR.
    
    /* Skip Employee if no Family members */
    IF NOT AVAILABLE Family THEN NEXT.
    
    /* Export Employee record */
    PUT UNFORMATTED
        '"' + STRING(Employee.EmpNum) + '";' +
        '"Employee";' +
        '"' + TRIM(Employee.FirstName) + '";' +
        '"' + TRIM(Employee.LastName) + '";' +
        '"' + STRING(Employee.Birthdate, "9999-99-99") + '"' SKIP.
    
    iEmpCount = iEmpCount + 1.
    
    /* Export Family members sorted by Birthdate descending */
    FOR EACH Family NO-LOCK
        WHERE Family.EmpNum = Employee.EmpNum
        BY Family.Birthdate DESCENDING:
        
        DEFINE VARIABLE cFirstName AS CHARACTER NO-UNDO.
        DEFINE VARIABLE cLastName  AS CHARACTER NO-UNDO.
        
        /* Extract first and last name from RelativeName */
        IF NUM-ENTRIES(TRIM(Family.RelativeName), " ") >= 2 THEN DO:
            cFirstName = ENTRY(1, TRIM(Family.RelativeName), " ").
            cLastName = ENTRY(2, TRIM(Family.RelativeName), " ").
        END.
        ELSE DO:
            cFirstName = "".
            cLastName = TRIM(Family.RelativeName).
        END.
        
        PUT UNFORMATTED
            '"";' +
            '"' + TRIM(Family.Relation) + '";' +
            '"' + cFirstName + '";' +
            '"' + cLastName + '";' +
            '"' + (IF Family.Birthdate <> ? 
                   THEN STRING(Family.Birthdate, "9999-99-99") 
                   ELSE "") + '"' SKIP.
        
        iFamilyCount = iFamilyCount + 1.
    END.
END.

/* Write totals line */
PUT UNFORMATTED
    '"Total Employees";"' + STRING(iEmpCount) + '";' +
    '"Total Family Members";"' + STRING(iFamilyCount) + '"' SKIP.

OUTPUT CLOSE.

/* Disconnect */
DISCONNECT sports2020 NO-ERROR.

/* Display summary */
MESSAGE 
    "Report generated successfully!" SKIP(1)
    "File: " + cReportFile SKIP
    "Employees exported: " + STRING(iEmpCount) SKIP
    "Family members exported: " + STRING(iFamilyCount)
    VIEW-AS ALERT-BOX INFORMATION.

/* Display in console as well */
DISPLAY
    "========================================" SKIP
    "Report Generation Completed" SKIP
    "========================================" SKIP
    "Report File: " + cReportFile SKIP
    "Employees Exported: " + STRING(iEmpCount) SKIP
    "Family Members Exported: " + STRING(iFamilyCount) SKIP
    "========================================" 
    WITH FRAME frmSummary NO-LABELS WIDTH 80.