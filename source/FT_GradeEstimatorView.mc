import Toybox.Activity;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Edge 540 personal edition: a single full-width, three-column data field.
class GradeEstimatorView extends WatchUi.DataField {
    var SAMPLE_WINDOW = 20;
    var MIN_GRADE_WINDOW = 7;
    var MAX_GRADE_WINDOW = 20;
    var THRESHOLD_LIGHT = 0.035;
    var THRESHOLD_STEEP = 0.08;
    var DIST_LOG_QUALITY = 0.1;
    var MAX_LOG_QUALITY = 0.5;
    const MAX_ALLOWED_GRADE = 0.3;
    const DISTANCE_FIELD_CAPACITY = 32;

    var altitudes as Array<Float> = [];
    var sampleDistances as Array<Float> = [];
    var regressionDistances as Array<Float> = [];
    var bufIndex = 0;
    var numValid = 0;
    var gradeWindowSize = 7;
    var prevAltitude as Float or Null = null;
    var lastSample as Float or Null = null;
    var grade = 0.0;
    var maxGrade = 0.0;
    var vam = 0.0;
    var quality = 0.0;
    var calculating = false;
    var distLight = 0.0;
    var distSteep = 0.0;
    var totalAscent as Number or Null = null;
    var isMetric = true;
    var timerState = Activity.TIMER_STATE_OFF;

    var LOGGING_ENALBED = true;
    var GRADE_LOGGING_ENALBED = false;
    var FIELD_SETUP_ERROR = false;
    var gradeField;
    var climbDistField;
    var lightLabel = "";
    var steepLabel = "";
    var fontChoices = [Graphics.FONT_SYSTEM_NUMBER_MEDIUM,Graphics.FONT_SYSTEM_MEDIUM,
        Graphics.FONT_SYSTEM_SMALL,Graphics.FONT_SYSTEM_TINY,Graphics.FONT_SYSTEM_XTINY];
    var fontHeights = null;
    var labelTexts = [null,null,null,null,null,null];
    var labelFonts = [0,0,0,0,0,0];
    var labelWidths = [0,0,0,0,0,0];
    var labelHeights = [0,0,0,0,0,0];
    var valueTexts = [null,null,null,null,null,null,null];
    var valueFonts = [0,0,0,0,0,0,0];
    var valueWidths = [0,0,0,0,0,0,0];
    var valueHeights = [0,0,0,0,0,0,0];

    function initialize() {
        DataField.initialize();
        isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
        updateSettings();
    }

    function readNumber(key as String, fallback as Float) as Float {
        var value = Application.Properties.getValue(key);
        return (value instanceof Number || value instanceof Float) ? value.toFloat() : fallback;
    }

    function clamp(value as Float, low as Float, high as Float) as Float {
        if (value < low) { return low; }
        if (value > high) { return high; }
        return value;
    }

    function updateSettings() {
        MIN_GRADE_WINDOW = clamp(readNumber("buffer_fit_min",7.0),3.0,180.0).toNumber();
        MAX_GRADE_WINDOW = clamp(readNumber("buffer_fit_max",20.0),MIN_GRADE_WINDOW.toFloat(),180.0).toNumber();
        SAMPLE_WINDOW = MAX_GRADE_WINDOW;
        DIST_LOG_QUALITY = clamp(readNumber("threshold_log_dist",0.1),0.0,1.0);
        MAX_LOG_QUALITY = clamp(readNumber("threshold_log_max",0.5),0.0,1.0);
        THRESHOLD_LIGHT = clamp(readNumber("threshold_light",3.5),0.0,30.0) / 100.0;
        THRESHOLD_STEEP = clamp(readNumber("threshold_steep",8.0),THRESHOLD_LIGHT*100.0,30.0) / 100.0;
        lightLabel = "Climb " + (THRESHOLD_LIGHT*100).format("%.1f") + "%+";
        steepLabel = "Hard " + (THRESHOLD_STEEP*100).format("%.1f") + "%+";
        altitudes = [];
        sampleDistances = [];
        for (var i=0; i<SAMPLE_WINDOW; i++) {
            altitudes.add(0.0); sampleDistances.add(0.0);
        }
        regressionDistances = [];
        for (var i=0; i<MAX_GRADE_WINDOW; i++) { regressionDistances.add(0.0); }
        initializeFields();
        _resetAll();
    }

    function initializeFields() {
        var logging = Application.Properties.getValue("enable_logging");
        LOGGING_ENALBED = logging instanceof Boolean ? logging : true;
        var records = Application.Properties.getValue("enable_grade_logging");
        GRADE_LOGGING_ENALBED = records instanceof Boolean ? records : false;
        if (!LOGGING_ENALBED) { FIELD_SETUP_ERROR = false; return; }
        if (GRADE_LOGGING_ENALBED && gradeField == null) {
            try {
                gradeField = createField("Grade",30,FitContributor.DATA_TYPE_FLOAT,
                    {:mesgType=>FitContributor.MESG_TYPE_RECORD,:units=>"%"});
            } catch (ex) { System.println("Grade FIT field: " + ex.getErrorMessage()); }
        }
        if (climbDistField == null) {
            try {
                climbDistField = createField("Climb dist. light/hard",31,FitContributor.DATA_TYPE_STRING,
                    {:mesgType=>FitContributor.MESG_TYPE_SESSION,:units=>"",:count=>DISTANCE_FIELD_CAPACITY});
            } catch (ex) { System.println("Distance FIT field: " + ex.getErrorMessage()); }
        }
        FIELD_SETUP_ERROR = climbDistField == null || (GRADE_LOGGING_ENALBED && gradeField == null);
    }

    function shouldAccLightDist() as Boolean { return grade >= THRESHOLD_LIGHT && quality >= DIST_LOG_QUALITY; }
    function shouldAccSteepDist() as Boolean { return grade >= THRESHOLD_STEEP && quality >= DIST_LOG_QUALITY; }
    function shouldCalcMaxGrade() as Boolean {
        return quality >= MAX_LOG_QUALITY && (gradeWindowSize > MIN_GRADE_WINDOW || gradeWindowSize == MAX_GRADE_WINDOW);
    }

    function updateTotalAscent(info as Activity.Info) {
        timerState = info.timerState;
        // Read the device's native activity total independently of grade buffering.
        // Paused/stopped samples retain the last recorded total; reset clears it.
        if (timerState == Activity.TIMER_STATE_ON && info.totalAscent != null && info.totalAscent >= 0) {
            totalAscent = info.totalAscent;
        }
    }

    function compute(info as Activity.Info) as Number {
        updateTotalAscent(info);
        var speed    = (info has :currentSpeed) ? info.currentSpeed : null;
        var altitude = (info has :altitude) ? info.altitude : null;
        var elapsed = (info has :elapsedTime) ? info.elapsedTime : null;
        if (speed == null || altitude == null || elapsed == null ||
            info.timerState != Activity.TIMER_STATE_ON || speed <= 0.0) {
            _resetAll();
            return 0;
        }
        var eTime = elapsed / 1000.0;
        if (lastSample == null) {
            lastSample = eTime;
            prevAltitude = altitude;
            return 0;
        }
        var dt = eTime - lastSample;
        // A duplicate timestamp contributes neither distance nor duration.
        if (dt == 0.0) { return 0; }
        var sample_distance = speed * dt;
        if (sample_distance < 0.1 || dt < 0.0 || dt > 5.0 ||
            (prevAltitude != null && (altitude - prevAltitude).abs() > 10.0)) {
            _resetAll();
            lastSample = eTime;
            prevAltitude = altitude;
            return 0;
        }
        lastSample = eTime;
        prevAltitude = altitude;

        // Reuse each sample slot and track validity without scanning the buffer.
        altitudes[bufIndex] = altitude;
        sampleDistances[bufIndex] = sample_distance;
        bufIndex = (bufIndex + 1) % SAMPLE_WINDOW;
        if (numValid < SAMPLE_WINDOW) { numValid++; }

        if (numValid < MIN_GRADE_WINDOW) {
                return 0;
        }


        // Fixed windows need only the final regression and quality calculation.
        if (MIN_GRADE_WINDOW != MAX_GRADE_WINDOW) {
            // --- Adaptive window selection (new logic) ---
            // Compute main grade with current window size
            var mainGrade = computeWindowSlope(altitudes, sampleDistances, bufIndex, gradeWindowSize, SAMPLE_WINDOW);
            // Compute min grade with window size minimum (if enough samples)
            var minGrade = gradeWindowSize == MIN_GRADE_WINDOW ? mainGrade :
                computeWindowSlope(altitudes, sampleDistances, bufIndex, MIN_GRADE_WINDOW, SAMPLE_WINDOW);

            // Compare and adjust window size for next call
            var gradeDiff = (mainGrade - minGrade).abs();
            if (gradeDiff > 0.02)  { gradeWindowSize -= 3; }
            else if (gradeDiff > 0.015) { gradeWindowSize -= 2; }
            else if (gradeDiff > 0.0075)  { gradeWindowSize -= 1; }
            else if (gradeDiff < 0.004 && gradeWindowSize <= MAX_GRADE_WINDOW / 2)
                                        { gradeWindowSize += 1; }
            else if (gradeDiff < 0.002){ gradeWindowSize += 1; }

            // Clamp window size between min and max, and not more than numValid
            if (gradeWindowSize < MIN_GRADE_WINDOW) { gradeWindowSize = MIN_GRADE_WINDOW; }
            if (gradeWindowSize > MAX_GRADE_WINDOW) { gradeWindowSize = MAX_GRADE_WINDOW; }
            if (gradeWindowSize > numValid) { gradeWindowSize = numValid; }

        } else {
            gradeWindowSize = MIN_GRADE_WINDOW;
        }

        // Use the main grade window for regression and display
        computeLinearRegressionSlope(altitudes, sampleDistances, bufIndex, gradeWindowSize);
        if (grade > MAX_ALLOWED_GRADE) { grade = MAX_ALLOWED_GRADE;}
        else if (grade < -MAX_ALLOWED_GRADE) { grade = -MAX_ALLOWED_GRADE; }

        vam = speed * grade * 3600.0;

        // Accumulate distance in each zone if above threshold and quality is good enough
        if (shouldAccLightDist()) { distLight += sample_distance; }
        if (shouldAccSteepDist()) { distSteep += sample_distance; }
        if (grade > maxGrade && shouldCalcMaxGrade()) {
            maxGrade = grade;
        }

        writeRecordFields();

        prevAltitude = altitude;

        return 1;
    }

    function computeLinearRegressionSlope(samples as Array<Float>, distances as Array<Float>, bufIndex as Number, windowSize as Number) {
        var xVals = regressionDistances;
        var dist = 0.0;
        var sumX = 0.0, sumY = 0.0;
        calculating = true;

        // Use only the last windowSize samples
        for (var i = 0; i < windowSize; i++) {
            var idx = (bufIndex + SAMPLE_WINDOW - windowSize + i) % SAMPLE_WINDOW;
            dist += distances[idx];
            xVals[i] = dist;
            sumY += samples[idx];
            sumX += xVals[i];
        }
        var meanX = sumX / windowSize;
        var meanY = sumY / windowSize;

        var covXY = 0.0, varX = 0.0;
        for (var i = 0; i < windowSize; i++) {
            var idx = (bufIndex + SAMPLE_WINDOW - windowSize + i) % SAMPLE_WINDOW;
            var dx = xVals[i] - meanX;
            var dy = samples[idx] - meanY;
            covXY += dx * dy;
            varX += dx * dx;
        }

        grade = (varX > 0.0) ? (covXY / varX) : 0.0;
        var sse = 0.0;
        for (var i = 0; i < windowSize; i++) {
            var idx = (bufIndex + SAMPLE_WINDOW - windowSize + i) % SAMPLE_WINDOW;
            var measAltDelta = samples[idx] - meanY;
            var AltDelta = grade * (xVals[i] - meanX);
            var res = (AltDelta - measAltDelta);

            sse += res*res;
        }

        if (varX > 0.0) {
            var sem = Math.sqrt((sse / (windowSize - 2)) / varX);
            quality = 0.005 / (0.005 + sem); // Quality measure based on standard error of the slope
        }
        else {
            quality = 0.0; // No valid data
            calculating = false; // We don't really have any data. This should never happen.
        }
    }

    function computeWindowSlope(samples as Array<Float>, distances as Array<Float>, bufIndex as Number, windowSize as Number, bufferLen as Number) as Float {
        var xVals = regressionDistances;
        var dist = 0.0;
        var sumX = 0.0, sumY = 0.0;
        for (var i = 0; i < windowSize; i++) {
            var idx = (bufIndex + bufferLen - windowSize + i) % bufferLen;
            dist += distances[idx];
            xVals[i] = dist;
            sumY += samples[idx];
            sumX += xVals[i];
        }
        var meanX = sumX / windowSize;
        var meanY = sumY / windowSize;
        var covXY = 0.0, varX = 0.0;
        for (var i = 0; i < windowSize; i++) {
            var idx = (bufIndex + bufferLen - windowSize + i) % bufferLen;
            var dx = xVals[i] - meanX;
            var dy = samples[idx] - meanY;
            covXY += dx * dy;
            varX += dx * dx;
        }
        return (varX > 0.0) ? (covXY / varX) : 0.0;
    }

    hidden function _resetAll() as Void {
        bufIndex = 0;
        numValid = 0;
        gradeWindowSize = MIN_GRADE_WINDOW;
        calculating = false;
        grade = 0.0;
        quality = 0.0;
        vam = 0.0;
        lastSample = null;
        prevAltitude = null;
        writeRecordFields();
    }

    function onTimerStart() as Void { timerState = Activity.TIMER_STATE_ON; _resetAll(); }
    function onTimerResume() as Void { timerState = Activity.TIMER_STATE_ON; _resetAll(); }
    function onTimerPause() as Void {
        timerState = Activity.TIMER_STATE_PAUSED;
        writeSessionFields();
        _resetAll();
    }
    function onTimerStop() as Void {
        timerState = Activity.TIMER_STATE_OFF;
        writeSessionFields();
        _resetAll();
    }
    function onTimerReset() as Void {
        timerState = Activity.TIMER_STATE_OFF;
        totalAscent = null;
        maxGrade = 0.0;
        distLight = 0.0;
        distSteep = 0.0;
        initializeFields();
        _resetAll();
        writeSessionFields();
    }

    function getDistanceString(meters as Float) as String {
        var distance = isMetric ? meters : meters * 3.28084;
        if (distance < 1000.0) { return distance.format("%.0f") + (isMetric ? "m" : "ft"); }
        distance = isMetric ? meters / 1000.0 : meters / 1609.344;
        return distance.format(distance >= 99.95 ? "%.0f" : "%.1f") + (isMetric ? "km" : "mi");
    }

    function getAscentString() as String {
        if (totalAscent == null) { return "--"; }
        var value = isMetric ? totalAscent.toFloat() : totalAscent * 3.28084;
        return value.format("%.0f") + (isMetric ? "m" : "ft");
    }

    function writeRecordFields() {
        if (!LOGGING_ENALBED || !GRADE_LOGGING_ENALBED || gradeField == null) { return; }
        try { gradeField.setData(grade * 100.0); }
        catch (ex) { FIELD_SETUP_ERROR = true; }
    }

    function writeSessionFields() {
        if (!LOGGING_ENALBED || climbDistField == null) { return; }
        var value = getDistanceString(distLight) + "/" + getDistanceString(distSteep);
        if (value.length()+1 > DISTANCE_FIELD_CAPACITY) { value = "NA"; }
        try { climbDistField.setData(value); }
        catch (ex) { FIELD_SETUP_ERROR = true; }
    }

    function getStatusString() as String {
        if (FIELD_SETUP_ERROR) { return "FIT LOG ERR"; }
        if (timerState == Activity.TIMER_STATE_PAUSED) { return "PAUSED"; }
        if (timerState != Activity.TIMER_STATE_ON) { return "STOPPED"; }
        if (calculating) { return "ACTIVE " + (quality*100.0).format("%.0f") + "%"; }
        if (numValid > 0) { return "BUFFER " + numValid.format("%d") + "/" + MIN_GRADE_WINDOW.format("%d"); }
        return "NO DATA";
    }

    // Choose the largest legible font that fits the available cell, including units.
    function fitFont(dc as Graphics.Dc, text as String, width as Number, height as Number, numeric as Boolean) {
        if (fontHeights == null) {
            fontHeights = [];
            for (var i=0;i<fontChoices.size();i++) {
                fontHeights.add(dc.getFontHeight(fontChoices[i]));
            }
        }
        for (var i=numeric ? 0 : 3;i<fontChoices.size();i++) {
            if (fontHeights[i] <= height && dc.getTextWidthInPixels(text,fontChoices[i]) <= width) {
                return fontChoices[i];
            }
        }
        return Graphics.FONT_SYSTEM_XTINY;
    }

    function labelFont(dc, text, width, height, cell) {
        if (labelTexts[cell] == null || !labelTexts[cell].equals(text) ||
            labelWidths[cell] != width || labelHeights[cell] != height) {
            labelFonts[cell] = fitFont(dc,text,width,height,false);
            labelTexts[cell] = text;
            labelWidths[cell] = width;
            labelHeights[cell] = height;
        }
        return labelFonts[cell];
    }

    function valueFont(dc, text, width, height, cell) {
        if (valueTexts[cell] == null || !valueTexts[cell].equals(text) ||
            valueWidths[cell] != width || valueHeights[cell] != height) {
            valueFonts[cell] = fitFont(dc,text,width,height,cell != 6);
            valueTexts[cell] = text;
            valueWidths[cell] = width;
            valueHeights[cell] = height;
        }
        return valueFonts[cell];
    }

    function drawCell(dc as Graphics.Dc, label as String, value as String, x as Number, y as Number, width as Number, height as Number, cell as Number) {
        var labelHeight = (height*0.34).toNumber();
        var valueHeight = height-labelHeight;
        var center = x+width/2;
        dc.setClip(x,y,width,height);
        dc.drawText(center,y+labelHeight/2,labelFont(dc,label,width-2,labelHeight,cell),label,
            Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(center,y+labelHeight+valueHeight/2,valueFont(dc,value,width-2,valueHeight,cell),value,
            Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        dc.clearClip();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var bg = getBackgroundColor();
        var fg = bg == Graphics.COLOR_BLACK ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg,bg);
        dc.clear();
        var width = dc.getWidth();
        var height = dc.getHeight();
        // This edition intentionally requires a full-width field.
        if (width < 220 || height < 78) {
            var hint = "Use a larger field";
            dc.drawText(width/2,height/2,fitFont(dc,hint,width-4,height,false),hint,
                Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var statusHeight = (height*0.16).toNumber();
        if (statusHeight > 18) { statusHeight = 18; }
        var status = getStatusString();
        var fit = LOGGING_ENALBED ? "" : "FIT OFF";
        var statusFont = valueFont(dc,status,width-55,statusHeight,6);
        dc.drawText(2,statusHeight/2,statusFont,status,Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(width-2,statusHeight/2,statusFont,fit,Graphics.TEXT_JUSTIFY_RIGHT|Graphics.TEXT_JUSTIFY_VCENTER);
        var rowHeight = (height-statusHeight)/2;
        var colWidth = width/3;
        var current = calculating ? (grade*100.0).format("%+.1f")+"%" : "--";
        var currentVam = calculating ? (vam*(isMetric ? 1.0 : 3.28084)).format("%.0f") : "--";
        drawCell(dc,"Grade",current,0,statusHeight,colWidth,rowHeight,0);
        drawCell(dc,lightLabel,getDistanceString(distLight),colWidth,statusHeight,colWidth,rowHeight,1);
        drawCell(dc,"VAM "+(isMetric ? "m/h" : "ft/h"),currentVam,2*colWidth,statusHeight,width-2*colWidth,rowHeight,2);
        drawCell(dc,"Max Grade",(maxGrade*100.0).format("%.1f")+"%",0,statusHeight+rowHeight,colWidth,rowHeight,3);
        drawCell(dc,steepLabel,getDistanceString(distSteep),colWidth,statusHeight+rowHeight,colWidth,rowHeight,4);
        drawCell(dc,"Total Ascent",getAscentString(),2*colWidth,statusHeight+rowHeight,width-2*colWidth,rowHeight,5);
    }
}
