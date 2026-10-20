import Toybox.Lang;
import Toybox.Test;
import Toybox.Activity;
import Toybox.Application;
import Toybox.FitContributor;

function restoreTestProperties() {
    Application.Properties.setValue("enable_logging", false);
    Application.Properties.setValue("enable_grade_logging", false);
    Application.Properties.setValue("buffer_length", 35);
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

(:test)
function controlSteadyClimb(logger as Test.Logger) as Boolean {
    var v = originalView();
    warmClimb(v);
    logger.debug("CONTROL constant 10% climb: grade=" + (v.grade*100).toString() + "; VAM=" + v.vam.toString() + "; quality=" + v.quality.toString());
    return (v.grade - 0.1).abs() < 0.0001 && (v.vam - 1080).abs() < 0.1 && v.calculating;
}

(:test)
function controlHistogramQualityGate(logger as Test.Logger) as Boolean {
    var h = new Histogram(0.5);
    h.addData(8.0, 0.4);
    h.addData(8.0, 1.0);
    logger.debug("CONTROL quality gate: tracked=" + h.getTrackedSeconds().toString() + "; expected=1");
    return h.getTrackedSeconds() == 1;
}

(:test)
function bug01NoncontinuousHeldGrade(logger as Test.Logger) as Boolean {
    var split = new Histogram(0.5);
    var continuous = new Histogram(0.5);
    for (var i = 0; i < 100; i++) {
        split.addData((i < 5 || i >= 95) ? 12.0 : 0.0, 1.0);
        continuous.addData(i < 10 ? 12.0 : 0.0, 1.0);
    }
    split.compute(); continuous.compute();
    var a = split.getHighGradeForTime(10.0);
    var b = continuous.getHighGradeForTime(10.0);
    logger.debug("BUG01 split 5s@12%,90s@0%,5s@12%: actual=" + a.toString() + "; best continuous 10s average=6.0");
    logger.debug("BUG01 continuous 10s@12%,90s@0%: actual=" + b.toString() + "; expected=12.0");
    return (a-6.0).abs() < 0.01 && (b-12.0).abs() < 0.01;
}

(:test)
function bug02BoundaryAndInsufficientTime(logger as Test.Logger) as Boolean {
    var h = new Histogram(0.5);
    for (var i = 0; i < 60; i++) { h.addData(8.0, 1.0); }
    h.compute();
    var actual = h.getHighGradeForTime(60.0);
    logger.debug("BUG02 60x8% query60s=" + actual.toString() + "; expected=8.0");
    logger.debug("BUG02 60x8% query1800s=" + (h.getHighGradeForTime(1800.0) == null).toString() + "; expected=unavailable");
    return (actual-8.0).abs() < 0.01 && h.getHighGradeForTime(1800.0) == null;
}

(:test)
function bug02FlatRoadQuantization(logger as Test.Logger) as Boolean {
    var h = new Histogram(0.5);
    for (var i = 0; i < 600; i++) { h.addData(0.0, 1.0); }
    h.compute();
    var actual = h.getHighGradeForTime(10.0);
    logger.debug("BUG02 600x0% query10s=" + actual.toString() + "; display=" + actual.format("%.1f") + "; expected=0.0");
    return actual.abs() < 0.01;
}

(:test)
function bug03IncompleteSessionReset(logger as Test.Logger) as Boolean {
    var v = originalView();
    v.maxGrade = 0.15; v.vam = 1000.0; v.vamAvg = 1000.0;
    v.sumAscentVam = 600000.0; v.samplesAscent = 600;
    v.lap_average_grade_sum = 5.0; v.lap_average_grade_count = 50;
    v.distLight = 1000.0; v.distSteep = 500.0;
    v.numValid = 35;
    v.onTimerReset();
    logger.debug("BUG03 reset: maxGrade=" + v.maxGrade.toString() + "; vamAvg=" + v.vamAvg.toString() + "; sumVam=" + v.sumAscentVam.toString() + "; samples=" + v.samplesAscent.toString());
    logger.debug("BUG03 reset: lapSum=" + v.lap_average_grade_sum.toString() + "; lapCount=" + v.lap_average_grade_count.toString() + "; numValid=" + v.numValid.toString() + "; light=" + v.distLight.toString());
    for (var i = 0; i < 600; i++) { v.grade=0.1; v.quality=1.0; v.computeVAM(0.1, 500.0/360.0); }
    logger.debug("BUG03 next activity 600 samples@500m/h: average=" + v.vamAvg.toString() + "; expected=500");
    return v.maxGrade == 0.0 && v.lap_average_grade_count == 0 && (v.vamAvg-500.0).abs() < 0.1;
}

(:test)
function bug04PausedMovingStillAccumulates(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v);
    var light=v.distLight; var hard=v.distSteep; var hist=v.histogram.getTrackedSeconds(); var vamCount=v.samplesAscent; var lap=v.lap_average_grade_count;
    v.onTimerPause();
    for (var t=61; t<=90; t++) {
        var info=sample(t,3.0,100.0+0.3*t,Activity.TIMER_STATE_PAUSED);
        info.timerTime=60000;
        v.compute(info);
    }
    logger.debug("BUG04 30s moving while PAUSED, timerTime frozen: lightDelta="+(v.distLight-light).toString()+"; hardDelta="+(v.distSteep-hard).toString());
    logger.debug("BUG04 histDelta="+(v.histogram.getTrackedSeconds()-hist).toString()+"; vamCountDelta="+(v.samplesAscent-vamCount).toString()+"; lapCountDelta="+(v.lap_average_grade_count-lap).toString()+"; expected all=0");
    return v.distLight==light && v.distSteep==hard && v.histogram.getTrackedSeconds()==hist && v.samplesAscent==vamCount && v.lap_average_grade_count==lap;
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

// Only createField is intercepted. All initialization and retry logic is inherited unchanged.
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
function bug06FitFailureHiddenAndRetrySkipped(logger as Test.Logger) as Boolean {
    restoreTestProperties();
    var v=new ObservedFitView(); v.failFieldId=37;
    Application.Properties.setValue("enable_logging",true);
    v.initializeFields();
    var errorReported=v.FIELD_SETUP_ERROR;
    var firstAttempts=v.attemptedIds.size();
    logger.debug("BUG06 after injected field37 failure: distanceCreated="+(v.climbDistField!=null).toString()+"; maxCreated="+(v.maxGradeForTimeField!=null).toString()+"; lapCreated="+(v.lapAvgGradeField!=null).toString()+"; FIELD_SETUP_ERROR="+errorReported.toString());
    v.failFieldId=-1;
    v.initializeFields();
    logger.debug("BUG06 retry with fault removed: extraCreateCalls="+(v.attemptedIds.size()-firstAttempts).toString()+"; maxCreated="+(v.maxGradeForTimeField!=null).toString()+"; lapCreated="+(v.lapAvgGradeField!=null).toString());
    Application.Properties.setValue("enable_logging",false);
    return errorReported && v.maxGradeForTimeField!=null && v.lapAvgGradeField!=null;
}

(:test)
function bug08BufferLimitBypass(logger as Test.Logger) as Boolean {
    var v=originalView();
    Application.Properties.setValue("buffer_fit_max",200);
    v.updateSettings();
    logger.debug("BUG08 maxWindow=200: SAMPLE_WINDOW="+v.SAMPLE_WINDOW.toString()+"; actual buffer="+v.buffer.size().toString()+"; documented ceiling=180");
    var ok=v.SAMPLE_WINDOW<=180 && v.buffer.size()<=180;
    restoreTestProperties();
    return ok;
}

(:test)
function bug09HistogramQualityNotUpdated(logger as Test.Logger) as Boolean {
    var v=originalView();
    Application.Properties.setValue("threshold_log_max",0.9);
    v.updateSettings();
    v.histogram.addData(8.0,0.7);
    logger.debug("BUG09 threshold changed 0.5->0.9: viewThreshold="+v.MAX_LOG_QUALITY.toString()+"; histogramThreshold="+v.histogram.minQuality.toString()+"; accepted 0.7-quality samples="+v.histogram.getTrackedSeconds().toString()+"; expected=0");
    var ok=v.histogram.getTrackedSeconds()==0;
    restoreTestProperties();
    return ok;
}

(:test)
function controlFitStringFitsCapacity(logger as Test.Logger) as Boolean {
    restoreTestProperties();
    var v=new ObservedFitView(); v.isMetric=true;
    Application.Properties.setValue("enable_logging",true);
    v.initializeFields();
    v.distLight=99000.0; v.distSteep=12340.0;
    var text=v.getLoggedDistanceString(v.distLight)+"/"+v.getLoggedDistanceString(v.distSteep);
    logger.debug("CONTROL FIT string='"+text+"'; bytesWithNul="+(text.length()+1).toString()+"; declaredCapacity="+v.distanceCapacity.toString());
    v.writeSessionFields();
    logger.debug("CONTROL original writeSessionFields succeeded with native FIT fields");
    Application.Properties.setValue("enable_logging",false);
    return text.length()+1<=v.distanceCapacity;
}

(:test)
function bug10FitStringCapacity(logger as Test.Logger) as Boolean {
    restoreTestProperties();
    var v=new ObservedFitView(); v.isMetric=true;
    Application.Properties.setValue("enable_logging",true);
    v.initializeFields();
    v.distLight=99960.0; v.distSteep=12340.0;
    var text=v.getLoggedDistanceString(v.distLight)+"/"+v.getLoggedDistanceString(v.distSteep);
    var needed=text.length()+1;
    logger.debug("BUG10 actual FIT string='"+text+"'; characters="+text.length().toString()+"; bytesWithNul="+needed.toString()+"; declaredCapacity="+v.distanceCapacity.toString());
    var accepted=true;
    try { v.writeSessionFields(); }
    catch(ex) { accepted=false; logger.debug("BUG10 native setData exception: "+ex.toString()); }
    logger.debug("BUG10 native writeSessionFields returned without exception="+accepted.toString());
    Application.Properties.setValue("enable_logging",false);
    return needed<=v.distanceCapacity;
}

(:test)
function bug11IrregularSamplingWeight(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v);
    v.sumAscentVam=0.0; v.samplesAscent=0; v.vamAvg=0.0;
    v.histogram=new Histogram(0.5);
    v.compute(sample(61,6.0,118.6,Activity.TIMER_STATE_ON));
    var firstVam=v.vam;
    v.compute(sample(66,3.0,120.1,Activity.TIMER_STATE_ON));
    var secondVam=v.vam;
    var weighted=(firstVam+5.0*secondVam)/6.0;
    logger.debug("BUG11 dt=1s VAM="+firstVam.toString()+"; dt=5s VAM="+secondVam.toString());
    logger.debug("BUG11 average="+v.vamAvg.toString()+"; timeWeightedExpected="+weighted.toString()+"; trackedSeconds="+v.histogram.getTrackedSeconds().toString()+"; represented elapsed=6s");
    return (v.vamAvg-weighted).abs()<0.1 && v.histogram.getTrackedSeconds()==6;
}

// Last: a VM-level arithmetic error may be uncatchable; it must not hide other cases.
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
function regressionContinuityAndAvailability(logger as Test.Logger) as Boolean {
    var h = new Histogram(0.5);
    for (var i=0; i<5; i++) { h.addData(12.0, 1.0); }
    h.addData(12.0, 0.4);
    for (var i=0; i<5; i++) { h.addData(12.0, 1.0); }
    if (h.getHighGradeForTime(10.0) != null) { return false; }
    for (var i=0; i<5; i++) { h.addData(12.0, 1.0); }
    if ((h.getHighGradeForTime(10.0)-12.0).abs()>0.001) { return false; }
    h.breakSequence();
    for (var i=0; i<9; i++) { h.addData(30.0, 1.0); }
    return (h.getHighGradeForTime(10.0)-12.0).abs()<0.001 && h.getHighGradeForTime(60.0)==null;
}

(:test)
function regressionFractionalTimeIntegration(logger as Test.Logger) as Boolean {
    var h = new Histogram(0.5);
    for (var i=0; i<10; i++) {
        h.addTimedData(5.0, 1.0, 0.25);
        h.addTimedData(10.0, 1.0, 0.75);
    }
    return (h.getTrackedSeconds()-10.0).abs()<0.001 && (h.getHighGradeForTime(10.0)-8.75).abs()<0.001;
}

(:test)
function regressionPauseResumeAndMissingData(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v);
    var before=v.distLight;
    v.onTimerPause(); v.onTimerResume();
    v.compute(sample(65,3.0,119.5,Activity.TIMER_STATE_ON));
    if (v.distLight!=before || v.calculating) { return false; }
    for (var t=66; t<=100; t++) { v.compute(sample(t,3.0,100.0+0.3*t,Activity.TIMER_STATE_ON)); }
    if (!v.calculating || v.distLight<=before) { return false; }
    v.compute(sample(101,3.0,null,Activity.TIMER_STATE_ON));
    before=v.distLight;
    v.compute(sample(102,3.0,130.6,Activity.TIMER_STATE_ON));
    if (v.calculating || v.distLight!=before) { return false; }
    v.compute(sample(108,3.0,132.4,Activity.TIMER_STATE_ON));
    return !v.calculating && v.distLight==before && v.histogram.getHighGradeForTime(60.0)==null;
}

(:test)
function regressionDuplicateAndBackwardClock(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v);
    var before=v.distLight;
    var seconds=v.histogram.getTrackedSeconds();
    v.compute(sample(60,3.0,118.0,Activity.TIMER_STATE_ON));
    if (v.distLight!=before || v.histogram.getTrackedSeconds()!=seconds) { return false; }
    v.compute(sample(59,3.0,117.7,Activity.TIMER_STATE_ON));
    return !v.calculating && v.numValid==0 && v.distLight==before;
}

(:test)
function regressionSettingsBounds(logger as Test.Logger) as Boolean {
    var v=originalView();
    Application.Properties.setValue("buffer_length",-5);
    Application.Properties.setValue("buffer_fit_min",300);
    Application.Properties.setValue("buffer_fit_max",-10);
    Application.Properties.setValue("threshold_log_max",2);
    Application.Properties.setValue("threshold_log_dist",-1);
    v.updateSettings();
    var ok=v.MIN_GRADE_WINDOW==180 && v.MAX_GRADE_WINDOW==180 && v.buffer.size()==180 &&
        v.MAX_LOG_QUALITY==1.0 && v.histogram.minQuality==1.0 && v.DIST_LOG_QUALITY==0.0;
    restoreTestProperties();
    return ok;
}

(:test)
function regressionLapTimeWeight(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v); v.onTimerLap();
    v.compute(sample(61,6.0,118.6,Activity.TIMER_STATE_ON));
    var first=v.grade;
    v.compute(sample(66,3.0,120.1,Activity.TIMER_STATE_ON));
    var expected=(first+5.0*v.grade)/6.0;
    return v.lap_average_grade_count==6.0 && (v.lap_average_grade_sum/6.0-expected).abs()<0.0001;
}

(:test)
function regressionFitNegativeAndLargeValues(logger as Test.Logger) as Boolean {
    restoreTestProperties(); var v=new ObservedFitView();
    Application.Properties.setValue("enable_logging",true); v.initializeFields();
    for (var i=0; i<1800; i++) { v.histogram.addData(-30.0,1.0); }
    v.distLight=1.0e35; v.distSteep=1.0e35;
    v.writeSessionFields();
    Application.Properties.setValue("enable_logging",false);
    logger.debug("Negative 30min FIT="+v.getLoggedHeldGrade(1800.0)+"; fieldError="+v.FIELD_SETUP_ERROR.toString());
    return v.getLoggedHeldGrade(1800.0).equals("-30.0") && !v.FIELD_SETUP_ERROR;
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
function regressionSessionResetAndSecondRide(logger as Test.Logger) as Boolean {
    var v=originalView(); warmClimb(v); v.onTimerReset();
    if (v.maxGrade!=0.0 || v.vamAvg!=0.0 || v.samplesAscent!=0 || v.sumAscentVam!=0.0 ||
        v.lap_average_grade_count!=0 || v.lap_average_grade_sum!=0.0 || v.numValid!=0 ||
        v.histogram.getTrackedSeconds()!=0 || v.histogram.getHighGradeForTime(10.0)!=null ||
        !v.getHeldGradeString(10.0).equals("--") || !v.getLoggedHeldGrade(10.0).equals("NA")) { return false; }
    for (var t=1; t<=60; t++) { v.compute(sample(t,3.0,100.0+0.15*t,Activity.TIMER_STATE_ON)); }
    logger.debug("Second ride grade="+v.grade.toString()+"; averageVAM="+v.vamAvg.toString()+"; max="+v.maxGrade.toString());
    return (v.grade-0.05).abs()<0.001 && (v.vamAvg-540.0).abs()<0.1 && v.maxGrade<0.051;
}

(:test)
function regressionTwoHourRollingWindows(logger as Test.Logger) as Boolean {
    var h=new Histogram(0.5);
    for (var i=0; i<7200; i++) { h.addData(((i*37)%101-50)/5.0,1.0); }
    // Independent offline brute-force sliding sums of the deterministic sequence.
    var windows=[10.0,60.0,300.0,600.0,900.0,1200.0,1800.0];
    var expected=[1.600000000,0.233333333,0.039333333,0.029333333,0.019333333,0.015666667,0.011777778];
    for (var i=0; i<windows.size(); i++) {
        var actual=h.getHighGradeForTime(windows[i]);
        logger.debug("window="+windows[i].toString()+" actual="+actual.toString()+" expected="+expected[i].toString());
        if ((actual-expected[i]).abs()>0.001) { return false; }
    }
    return h.getTrackedSeconds()==7200;
}
