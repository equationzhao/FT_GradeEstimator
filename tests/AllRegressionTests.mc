import Toybox.Lang;
import Toybox.Test;
import Toybox.Activity;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.System;
import Toybox.Graphics;

class RecordingDisplayView extends GradeEstimatorView {
    var renderedValues=["","","","","",""];
    function initialize() { GradeEstimatorView.initialize(); }
    function drawCell(dc,label,value,x,y,width,height,cell) {
        renderedValues[cell]=value;
        GradeEstimatorView.drawCell(dc,label,value,x,y,width,height,cell);
    }
}

(:test)
function displayFormattingMatchesNative(logger as Test.Logger) as Boolean {
    restoreTestProperties(); var view=new RecordingDisplayView();
    var bitmap=Graphics.createBufferedBitmap({:width=>246,:height=>106,
        :palette=>[Graphics.COLOR_BLACK,Graphics.COLOR_WHITE]}).get();
    var dc=bitmap.getDc();
    var cases=[-0.0,0.0,-0.0005,0.0005,0.034999,0.035,0.035001,0.079999,0.08,0.080001,0.3,-0.3];
    var distances=[0.0,999.4,999.5,999.99,1000.0,99949.0,99950.0,99960.0,1609.344,100000.0,12310.0,12320.0];
    view.onUpdate(dc);
    for (var unit=0;unit<2;unit++) {
        view.isMetric=unit==0;
        for (var i=0;i<cases.size();i++) {
            view.calculating=true; view.timerState=Activity.TIMER_STATE_ON;
            view.grade=cases[i]; view.maxGrade=cases[i].abs();
            view.vam=cases[i]*10800.0; view.distLight=distances[i]; view.distSteep=distances[i];
            view.totalAscent=i; view.quality=0.995;
            for (var repeat=0;repeat<2;repeat++) {
                view.onUpdate(dc);
                var ascent=(view.isMetric ? i.toFloat() : i*3.28084).format("%.0f")+(view.isMetric ? "m" : "ft");
                if (!view.renderedValues[0].equals((view.grade*100.0).format("%+.1f")+"%") ||
                    !view.renderedValues[1].equals(view.getDistanceString(view.distLight)) ||
                    !view.renderedValues[2].equals((view.vam*(view.isMetric ? 1.0 : 3.28084)).format("%.0f")) ||
                    !view.renderedValues[3].equals((view.maxGrade*100.0).format("%.1f")+"%") ||
                    !view.renderedValues[4].equals(view.getDistanceString(view.distSteep)) ||
                    !view.renderedValues[5].equals(ascent) ||
                    !view.getStatusString().equals("ACTIVE "+(view.quality*100.0).format("%.0f")+"%")) {
                    logger.error("Display mismatch unit="+unit+" case="+i);
                    return false;
                }
            }
        }
    }
    view.onTimerPause(); view.onUpdate(dc);
    if (!view.renderedValues[0].equals("--") || !view.getStatusString().equals("PAUSED")) { return false; }
    view.onTimerReset(); view.onUpdate(dc);
    return view.renderedValues[5].equals("--") && view.renderedValues[1].equals("0ft");
}

function referenceFont(dc, text, width, height, numeric) {
    var fonts=numeric ? [Graphics.FONT_SYSTEM_NUMBER_MEDIUM,Graphics.FONT_SYSTEM_MEDIUM,
        Graphics.FONT_SYSTEM_SMALL,Graphics.FONT_SYSTEM_TINY,Graphics.FONT_SYSTEM_XTINY] :
        [Graphics.FONT_SYSTEM_TINY,Graphics.FONT_SYSTEM_XTINY];
    for (var i=0;i<fonts.size();i++) {
        if (dc.getTextWidthInPixels(text,fonts[i])<=width && dc.getFontHeight(fonts[i])<=height) {
            return fonts[i];
        }
    }
    return Graphics.FONT_SYSTEM_XTINY;
}

(:test)
function labelCacheInvalidation(logger as Test.Logger) as Boolean {
    var bitmap=Graphics.createBufferedBitmap({:width=>246,:height=>106,
        :palette=>[Graphics.COLOR_BLACK,Graphics.COLOR_WHITE]}).get();
    var dc=bitmap.getDc(); var view=originalView();
    // The first rendering must work before any activity sample exists.
    view.onUpdate(dc);
    var labels=["Grade","VAM m/h","VAM ft/h","Climb 30.0%+","Total Ascent"];
    for (var i=0;i<labels.size();i++) {
        for (var width=30;width<=90;width+=30) {
            for (var height=10;height<=20;height+=5) {
                var expected=referenceFont(dc,labels[i],width,height,false);
                if (view.labelFont(dc,labels[i],width,height,0)!=expected ||
                    view.labelFont(dc,labels[i],width,height,0)!=expected) { return false; }
            }
        }
    }
    Application.Properties.setValue("threshold_light",12.5);
    view.updateSettings(); view.isMetric=false; view.onUpdate(dc);
    var ok=view.labelTexts[1].equals("Climb 12.5%+") && view.labelTexts[2].equals("VAM ft/h");
    restoreTestProperties();
    return ok;
}

(:test)
function valueCacheInvalidation(logger as Test.Logger) as Boolean {
    var bitmap=Graphics.createBufferedBitmap({:width=>246,:height=>106,
        :palette=>[Graphics.COLOR_BLACK,Graphics.COLOR_WHITE]}).get();
    var dc=bitmap.getDc(); var view=originalView();
    var values=["11111","88888","-30.0%","+0.0%","--","99999ft","1286m","STOPPED","FIT LOG ERR"];
    for (var i=0;i<values.size();i++) {
        for (var width=30;width<=90;width+=30) {
            for (var height=10;height<=30;height+=10) {
                for (var cell=0;cell<=6;cell+=6) {
                    var expected=referenceFont(dc,values[i],width,height,cell!=6);
                    if (view.valueFont(dc,values[i],width,height,cell)!=expected ||
                        view.valueFont(dc,values[i],width,height,cell)!=expected) { return false; }
                }
            }
        }
    }
    return true;
}

(:test)
function wideLayoutFontsFit(logger as Test.Logger) as Boolean {
    var bitmap = Graphics.createBufferedBitmap({
        :width=>246, :height=>106,
        :palette=>[Graphics.COLOR_BLACK,Graphics.COLOR_WHITE]
    }).get();
    var dc = bitmap.getDc();
    var view = originalView();
    var labels = ["Grade","Climb 30.0%+","VAM ft/h","Max Grade","Hard 30.0%+","Total Ascent"];
    var values = ["-30.0%","999km","-99999","30.0%","999mi","99999ft"];
    var heights = [78,106,160];
    for (var h=0;h<heights.size();h++) {
        var height=heights[h];
        var statusHeight = (height*0.16).toNumber();
        if (statusHeight > 18) { statusHeight=18; }
        var rowHeight=(height-statusHeight)/2;
        var labelHeight=(rowHeight*0.34).toNumber();
        for (var i=0;i<labels.size();i++) {
            var font=view.fitFont(dc,labels[i],80,labelHeight,false);
            if (dc.getTextWidthInPixels(labels[i],font)>80 || dc.getFontHeight(font)>labelHeight) {
                logger.error("Label does not fit: "+labels[i]+" at height "+height);
                return false;
            }
            font=view.fitFont(dc,values[i],80,rowHeight-labelHeight,true);
            if (dc.getTextWidthInPixels(values[i],font)>80 || dc.getFontHeight(font)>rowHeight-labelHeight) {
                logger.error("Value does not fit: "+values[i]+" at height "+height);
                return false;
            }
        }
    }
    return true;
}

function restoreTestProperties() {
    Application.Properties.setValue("enable_logging", false);
    Application.Properties.setValue("enable_grade_logging", false);
    Application.Properties.setValue("buffer_fit_min", 7);
    Application.Properties.setValue("buffer_fit_max", 20);
    Application.Properties.setValue("threshold_log_dist", 0.1);
    Application.Properties.setValue("threshold_log_max", 0.5);
    Application.Properties.setValue("threshold_light", 3.5);
    Application.Properties.setValue("threshold_steep", 8.0);
}

function originalView() {
    restoreTestProperties();
    return new GradeEstimatorView();
}

function sample(seconds, speed, altitude, state) {
    var info = Activity.getActivityInfo();
    info.totalAscent = null;
    info.currentSpeed = speed;
    info.altitude = altitude;
    info.elapsedTime = seconds * 1000;
    info.timerTime = seconds * 1000;
    info.timerState = state;
    return info;
}

function warmClimb(v) {
    for (var t = 1; t <= 60; t++) {
        v.compute(sample(t, 3.0, 100.0 + 0.3 * t, Activity.TIMER_STATE_ON));
    }
}

class ObservedFitView extends GradeEstimatorView {
    var failFieldId=-1;
    var attemptedIds=[];
    var distanceCapacity=0;
    function initialize() { GradeEstimatorView.initialize(); }
    function createField(name,fieldId,type,options) {
        attemptedIds.add(fieldId);
        if (fieldId==31) { distanceCapacity=options[:count]; }
        if (fieldId==failFieldId) { throw new Lang.InvalidValueException("Injected createField failure"); }
        return GradeEstimatorView.createField(name,fieldId,type,options);
    }
}

(:test)
function controlSteadyClimb(logger as Test.Logger) as Boolean {
    var v = originalView();
    warmClimb(v);
    logger.debug("CONTROL constant 10% climb: grade=" + (v.grade*100).toString() + "; VAM=" + v.vam.toString() + "; quality=" + v.quality.toString());
    return (v.grade - 0.1).abs() < 0.0001 && (v.vam - 1080).abs() < 0.1 && v.calculating;
}

(:test)
function bug04StoppedTimerStillAccumulates(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v);
    var before=v.distLight;
    v.onTimerStop();
    var info=sample(61,3.0,118.3,Activity.TIMER_STATE_OFF);
    info.timerTime=60000;
    v.compute(info);
    logger.debug("BUG04 after onTimerStop, OFF + moving: lightDelta="+(v.distLight-before).toString()+"; expected=0");
    return v.distLight==before;
}

(:test)
function bug05StoppedSpeedStaleVam(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v);
    var old=v.vam;
    v.compute(sample(61,0.0,118.0,Activity.TIMER_STATE_ON));
    logger.debug("BUG05 stopped speed=0: beforeVAM="+old.toString()+"; afterVAM="+v.vam.toString()+"; calculating="+v.calculating.toString()+"; numValid="+v.numValid.toString()+"; expected VAM=0,numValid=0");
    return v.vam==0.0 && v.numValid==0;
}

(:test)
function bug05MissingAltitudeStillActive(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v);
    v.compute(sample(61,3.0,null,Activity.TIMER_STATE_ON));
    logger.debug("BUG05 null altitude: calculating="+v.calculating.toString()+"; grade="+v.grade.toString()+"; VAM="+v.vam.toString()+"; expected calculating=false");
    return !v.calculating;
}

(:test)
function bug08BufferLimitBypass(logger as Test.Logger) as Boolean {
    var v=originalView();
    Application.Properties.setValue("buffer_fit_max",200);
    v.updateSettings();
    logger.debug("BUG08 maxWindow=200: SAMPLE_WINDOW="+v.SAMPLE_WINDOW.toString()+"; actual buffer="+v.altitudes.size().toString()+"; documented ceiling=180");
    var ok=v.SAMPLE_WINDOW<=180 && v.altitudes.size()<=180;
    restoreTestProperties();
    return ok;
}

(:test)
function bug07NullElapsedTime(logger as Test.Logger) as Boolean {
    var v=originalView();
    var info=sample(1,3.0,100.0,Activity.TIMER_STATE_ON);
    info.elapsedTime=null;
    logger.debug("BUG07 calling original compute with elapsedTime=null, speed=3, altitude=100");
    try {
        v.compute(info);
        logger.debug("BUG07 compute returned normally");
        Application.Properties.setValue("enable_logging",false);
        return true;
    } catch(ex) {
        logger.debug("BUG07 caught UnexpectedTypeException="+(ex instanceof Lang.UnexpectedTypeException).toString()+"; message="+ex.getErrorMessage());
        Application.Properties.setValue("enable_logging",false);
        return false;
    }
}

(:test)
function regressionFitToggleReusesRegistrations(logger as Test.Logger) as Boolean {
    restoreTestProperties(); var v=new ObservedFitView();
    Application.Properties.setValue("enable_logging",true);
    Application.Properties.setValue("enable_grade_logging",true); v.initializeFields();
    var initial=v.attemptedIds.size(); var field=v.gradeField;
    Application.Properties.setValue("enable_grade_logging",false); v.initializeFields();
    Application.Properties.setValue("enable_grade_logging",true); v.initializeFields();
    var ok=v.attemptedIds.size()==initial && v.gradeField==field && !v.FIELD_SETUP_ERROR;
    restoreTestProperties(); return ok;
}

(:test)
function pausedMovementDoesNotAccumulate(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v);
    var light=v.distLight; var hard=v.distSteep; var maximum=v.maxGrade;
    v.onTimerPause();
    for (var t=61; t<=90; t++) { v.compute(sample(t,3.0,100.0+0.3*t,Activity.TIMER_STATE_PAUSED)); }
    return v.distLight==light && v.distSteep==hard && v.maxGrade==maximum && !v.calculating;
}

(:test)
function resumeStartsFreshWindow(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v); var before=v.distLight;
    v.onTimerPause(); v.onTimerResume();
    v.compute(sample(65,3.0,119.5,Activity.TIMER_STATE_ON));
    if (v.distLight!=before || v.calculating) { return false; }
    for (var t=66; t<=100; t++) { v.compute(sample(t,3.0,100.0+0.3*t,Activity.TIMER_STATE_ON)); }
    return v.calculating && v.distLight>before && (v.grade-0.1).abs()<0.0001;
}

(:test)
function sessionResetClearsOnlyOwnTotals(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v); v.totalAscent=1234; v.onTimerReset();
    if (v.totalAscent!=null || v.maxGrade!=0.0 || v.vam!=0.0 || v.distLight!=0.0 || v.distSteep!=0.0 || v.numValid!=0) { return false; }
    var stale=sample(61,0.0,118.0,Activity.TIMER_STATE_OFF); stale.totalAscent=1234; v.compute(stale);
    if (v.totalAscent!=null) { return false; }
    v.onTimerStart();
    for (var t=1; t<=60; t++) { v.compute(sample(t,3.0,100.0+0.15*t,Activity.TIMER_STATE_ON)); }
    return (v.grade-0.05).abs()<0.0001 && v.maxGrade<0.051;
}

(:test)
function totalAscentIndependentOfGrade(logger as Test.Logger) as Boolean {
    var v=originalView();
    var info=sample(1,0.0,null,Activity.TIMER_STATE_ON); info.totalAscent=1286; v.compute(info);
    if (v.totalAscent!=1286 || v.calculating) { return false; }
    info=sample(2,null,null,Activity.TIMER_STATE_ON); info.totalAscent=1287; v.compute(info);
    return v.totalAscent==1287 && !v.calculating;
}

(:test)
function totalAscentPauseNullAndZero(logger as Test.Logger) as Boolean {
    var v=originalView(); var info=sample(1,0.0,null,Activity.TIMER_STATE_ON);
    info.totalAscent=0; v.compute(info); v.isMetric=true;
    if (!v.getAscentString().equals("0m")) { return false; }
    info.totalAscent=100; info.elapsedTime=2000; v.compute(info);
    v.onTimerPause(); info.timerState=Activity.TIMER_STATE_PAUSED; info.totalAscent=150; v.compute(info);
    if (v.totalAscent!=100) { return false; }
    v.onTimerResume(); info.timerState=Activity.TIMER_STATE_ON; info.totalAscent=null; v.compute(info);
    if (v.totalAscent!=100) { return false; }
    info.totalAscent=160; v.compute(info);
    return v.totalAscent==160;
}

(:test)
function totalAscentUnitConversion(logger as Test.Logger) as Boolean {
    var v=originalView();
    if (!v.getAscentString().equals("--")) { return false; }
    v.totalAscent=1000; v.isMetric=true;
    if (!v.getAscentString().equals("1000m")) { return false; }
    v.isMetric=false;
    return v.getAscentString().equals("3281ft");
}

(:test)
function elapsedIntervalsAndDuplicateSamples(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v); var before=v.distLight;
    v.compute(sample(60,3.0,118.0,Activity.TIMER_STATE_ON));
    if (v.distLight!=before) { return false; }
    v.compute(sample(65,3.0,119.5,Activity.TIMER_STATE_ON));
    if ((v.distLight-before-15.0).abs()>0.01) { return false; }
    v.compute(sample(64,3.0,119.2,Activity.TIMER_STATE_ON));
    if (v.calculating || v.numValid!=0) { return false; }
    v.compute(sample(71,3.0,121.3,Activity.TIMER_STATE_ON));
    return !v.calculating && (v.distLight-before-15.0).abs()<0.01;
}

(:test)
function missingDataAndAltitudeJumpRestartBuffer(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v); var before=v.distLight;
    v.compute(sample(61,3.0,null,Activity.TIMER_STATE_ON));
    v.compute(sample(62,3.0,118.6,Activity.TIMER_STATE_ON));
    if (v.calculating || v.distLight!=before) { return false; }
    v.compute(sample(63,3.0,200.0,Activity.TIMER_STATE_ON));
    return !v.calculating && v.numValid==0 && v.distLight==before;
}

(:test)
function settingsStayBounded(logger as Test.Logger) as Boolean {
    var v=originalView();
    Application.Properties.setValue("buffer_fit_min",300);
    Application.Properties.setValue("buffer_fit_max",-10); Application.Properties.setValue("threshold_log_max",2);
    Application.Properties.setValue("threshold_log_dist",-1);
    v.updateSettings();
    var ok=v.altitudes.size()==180 && v.regressionDistances.size()==180 && v.MIN_GRADE_WINDOW==180 &&
        v.MAX_GRADE_WINDOW==180 && v.MAX_LOG_QUALITY==1.0 && v.DIST_LOG_QUALITY==0.0;
    restoreTestProperties(); return ok;
}

(:test)
function flatAndNegativeAltitudeRemainValid(logger as Test.Logger) as Boolean {
    var v=originalView();
    for (var t=1; t<=100; t++) { v.compute(sample(t,3.0,-600.0,Activity.TIMER_STATE_ON)); }
    if (!v.calculating || v.grade.abs()>0.0001 || v.distLight!=0.0) { return false; }
    v.onTimerReset();
    for (var t=1; t<=100; t++) { v.compute(sample(t,3.0,100.0-0.3*t,Activity.TIMER_STATE_ON)); }
    return v.calculating && (v.grade+0.1).abs()<0.0001 && v.distLight==0.0 && v.vam<0.0;
}

(:test)
function regressionQualityGateAndBufferReuse(logger as Test.Logger) as Boolean {
    var v=originalView(); var slots=v.altitudes; var distances=v.sampleDistances; var scratch=v.regressionDistances;
    warmClimb(v);
    if (v.altitudes!=slots || v.sampleDistances!=distances || v.regressionDistances!=scratch) { return false; }
    v.quality=0.0; v.grade=0.2;
    return !v.shouldAccLightDist() && !v.shouldAccSteepDist() && !v.shouldCalcMaxGrade();
}

(:test)
function partialFitFailureRemainsVisibleAndRetries(logger as Test.Logger) as Boolean {
    restoreTestProperties(); var v=new ObservedFitView(); v.failFieldId=31;
    Application.Properties.setValue("enable_logging",true); Application.Properties.setValue("enable_grade_logging",true);
    v.initializeFields();
    if (!v.FIELD_SETUP_ERROR || v.gradeField==null || v.climbDistField!=null || !v.getStatusString().equals("FIT LOG ERR")) { return false; }
    var attempts=v.attemptedIds.size(); v.failFieldId=-1; v.initializeFields();
    var ok=!v.FIELD_SETUP_ERROR && v.climbDistField!=null && v.attemptedIds.size()==attempts+1;
    restoreTestProperties(); return ok;
}

(:test)
function nativeFitCapacityAndReset(logger as Test.Logger) as Boolean {
    restoreTestProperties(); var v=new ObservedFitView();
    Application.Properties.setValue("enable_logging",true); v.initializeFields(); v.isMetric=true;
    v.distLight=99960.0; v.distSteep=12340.0; v.writeSessionFields();
    v.distLight=1.0e35; v.distSteep=1.0e35; v.writeSessionFields();
    v.onTimerReset();
    var ok=!v.FIELD_SETUP_ERROR && v.distanceCapacity<=32 && v.distLight==0.0;
    restoreTestProperties(); return ok;
}

(:test)
function loggingDisabledClearsObsoleteError(logger as Test.Logger) as Boolean {
    var v=originalView(); v.FIELD_SETUP_ERROR=true;
    v.initializeFields();
    return !v.FIELD_SETUP_ERROR && v.gradeField==null && v.climbDistField==null;
}

(:test)
function twoHourRideRemainsStable(logger as Test.Logger) as Boolean {
    var v=originalView();
    for (var t=1; t<=7200; t++) { v.compute(sample(t,3.0,100.0+0.3*t,Activity.TIMER_STATE_ON)); }
    logger.debug("2h grade="+v.grade.toString()+" distance="+v.distLight.toString());
    return v.calculating && (v.grade-0.1).abs()<0.001 && v.altitudes.size()==v.MAX_GRADE_WINDOW && v.sampleDistances.size()==v.MAX_GRADE_WINDOW &&
        v.regressionDistances.size()==20 && v.distLight>21000.0;
}
