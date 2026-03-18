public with sharing class WorkdayManagementUtil {
    public static final String DAY_STATUS_PLANNED = 'Planned';
    public static final String DAY_STATUS_ACTIVE = 'Active';
    public static final String DAY_STATUS_ON_BREAK = 'On Break';
    public static final String DAY_STATUS_ENDED = 'Ended';
    public static final String DAY_STATUS_AUTO_ENDED = 'Auto Ended';
    public static final String DAY_STATUS_LEAVE = 'Leave';

    public static final String BREAK_STATUS_IN_PROGRESS = 'In Progress';
    public static final String BREAK_STATUS_COMPLETED = 'Completed';
    public static final String BREAK_STATUS_AUTO_ENDED = 'Auto Ended';

    public static String buildAttendanceKey(Id employeeId, Date attendanceDate) {
        return String.valueOf(employeeId) + '-' + String.valueOf(attendanceDate);
    }

    public static String dayName(Date dateValue) {
        if (dateValue == null) {
            return null;
        }
        DateTime marker = DateTime.newInstance(dateValue, Time.newInstance(12, 0, 0, 0));
        return marker.format('EEEE');
    }

    public static Boolean isWorkingDay(Employee__c employee, Date dateValue) {
        if (employee == null || dateValue == null) {
            return false;
        }

        String currentDay = dayName(dateValue);
        if (String.isNotBlank(employee.Working_Days__c)) {
            Set<String> workingDays = new Set<String>();
            for (String token : employee.Working_Days__c.split(';')) {
                if (String.isNotBlank(token)) {
                    workingDays.add(token.trim());
                }
            }
            return workingDays.contains(currentDay);
        }

        if (String.isNotBlank(employee.Weekly_Off_Day__c)) {
            return currentDay != employee.Weekly_Off_Day__c;
        }

        return currentDay != 'Sunday';
    }

    public static Boolean isWithinBusinessWindow(Employee__c employee, DateTime dateTimeValue) {
        if (employee == null || dateTimeValue == null) {
            return true;
        }

        if (String.isNotBlank(employee.Business_Hours__c)) {
            try {
                Id businessHoursId = Id.valueOf(employee.Business_Hours__c);
                return BusinessHours.isWithin(businessHoursId, dateTimeValue);
            } catch (Exception ex) {
                // Fallback to shift window check.
            }
        }

        if (employee.Shift_Start_Time__c != null && employee.Shift_End_Time__c != null) {
            Integer nowMillis = toMillisOfDay(dateTimeValue.time());
            Integer startMillis = toMillisOfDay(employee.Shift_Start_Time__c);
            Integer endMillis = toMillisOfDay(employee.Shift_End_Time__c);

            if (startMillis <= endMillis) {
                return nowMillis >= startMillis && nowMillis <= endMillis;
            }

            // Overnight shift.
            return nowMillis >= startMillis || nowMillis <= endMillis;
        }

        return true;
    }

    public static Decimal minutesBetween(DateTime startValue, DateTime endValue) {
        if (startValue == null || endValue == null) {
            return 0;
        }
        Long diffMs = endValue.getTime() - startValue.getTime();
        if (diffMs <= 0) {
            return 0;
        }
        return (Decimal.valueOf(diffMs) / 60000).setScale(2);
    }

    public static void recalculateAttendance(
        Attendance__c attendance,
        List<Break_Time__c> breaks,
        DateTime referenceEnd
    ) {
        if (attendance == null) {
            return;
        }

        if (attendance.Start_Time__c == null) {
            attendance.Total_Break_Minutes__c = 0;
            attendance.Gross_Work_Minutes__c = 0;
            attendance.Net_Work_Minutes__c = 0;
            return;
        }

        DateTime effectiveEnd = attendance.End_Time__c != null ? attendance.End_Time__c : referenceEnd;
        if (effectiveEnd == null) {
            effectiveEnd = System.now();
        }

        Decimal totalBreak = 0;
        if (breaks != null) {
            for (Break_Time__c breakItem : breaks) {
                if (breakItem.Break_Start__c == null) {
                    continue;
                }
                DateTime breakEnd = breakItem.Break_End__c != null ? breakItem.Break_End__c : effectiveEnd;
                Decimal minutes = breakItem.Duration_Minutes__c;
                if (minutes == null || minutes <= 0) {
                    minutes = minutesBetween(breakItem.Break_Start__c, breakEnd);
                }
                if (minutes > 0) {
                    totalBreak += minutes;
                }
            }
        }

        Decimal grossMinutes = minutesBetween(attendance.Start_Time__c, effectiveEnd);
        Decimal netMinutes = grossMinutes - totalBreak;
        if (netMinutes < 0) {
            netMinutes = 0;
        }

        attendance.Total_Break_Minutes__c = totalBreak.setScale(2);
        attendance.Gross_Work_Minutes__c = grossMinutes.setScale(2);
        attendance.Net_Work_Minutes__c = netMinutes.setScale(2);
    }

    public static String buildDaySummary(Attendance__c attendance, List<Break_Time__c> breaks) {
        if (attendance == null) {
            return null;
        }

        List<String> lines = new List<String>();
        lines.add('Start: ' + formatDateTime(attendance.Start_Time__c));
        lines.add('End: ' + formatDateTime(attendance.End_Time__c));

        if (breaks == null || breaks.isEmpty()) {
            lines.add('Breaks: None');
        } else {
            lines.add('Breaks:');
            Integer indexValue = 1;
            for (Break_Time__c breakItem : breaks) {
                Decimal minutes = breakItem.Duration_Minutes__c;
                if (minutes == null && breakItem.Break_Start__c != null && breakItem.Break_End__c != null) {
                    minutes = minutesBetween(breakItem.Break_Start__c, breakItem.Break_End__c);
                }
                String lineValue =
                    String.valueOf(indexValue) +
                    '. ' +
                    formatTime(breakItem.Break_Start__c) +
                    ' - ' +
                    formatTime(breakItem.Break_End__c) +
                    ' (' +
                    formatDecimal(minutes) +
                    ' min)';
                lines.add(lineValue);
                indexValue++;
            }
        }

        lines.add('Total Break (min): ' + formatDecimal(attendance.Total_Break_Minutes__c));
        lines.add('Gross Work (hrs): ' + formatDecimal(divideBySixty(attendance.Gross_Work_Minutes__c)));
        lines.add('Net Work (hrs): ' + formatDecimal(divideBySixty(attendance.Net_Work_Minutes__c)));

        return String.join(lines, '\n');
    }

    public static String buildBreakTimeline(List<Break_Time__c> breaks) {
        if (breaks == null || breaks.isEmpty()) {
            return 'No breaks';
        }

        List<String> tokens = new List<String>();
        Integer indexValue = 1;
        for (Break_Time__c breakItem : breaks) {
            Decimal minutes = breakItem.Duration_Minutes__c;
            if (minutes == null && breakItem.Break_Start__c != null && breakItem.Break_End__c != null) {
                minutes = minutesBetween(breakItem.Break_Start__c, breakItem.Break_End__c);
            }

            String token =
                String.valueOf(indexValue) +
                ') ' +
                formatTime(breakItem.Break_Start__c) +
                '-' +
                formatTime(breakItem.Break_End__c) +
                ' (' +
                formatDecimal(minutes) +
                'm)';
            tokens.add(token);
            indexValue++;
        }

        return String.join(tokens, ' | ');
    }

    public static String formatDateTime(DateTime dateTimeValue) {
        if (dateTimeValue == null) {
            return '-';
        }
        return dateTimeValue.format('dd MMM yyyy, hh:mm a');
    }

    public static String formatTime(DateTime dateTimeValue) {
        if (dateTimeValue == null) {
            return '-';
        }
        return dateTimeValue.format('hh:mm a');
    }

    public static String formatDecimal(Decimal value) {
        if (value == null) {
            return '0.00';
        }
        return String.valueOf(value.setScale(2));
    }

    private static Decimal divideBySixty(Decimal minutesValue) {
        if (minutesValue == null) {
            return 0;
        }
        return (minutesValue / 60).setScale(2);
    }

    private static Integer toMillisOfDay(Time timeValue) {
        if (timeValue == null) {
            return 0;
        }
        return
            (timeValue.hour() * 60 * 60 * 1000) +
            (timeValue.minute() * 60 * 1000) +
            (timeValue.second() * 1000) +
            timeValue.millisecond();
    }
}