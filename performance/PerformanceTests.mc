import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;

// Off-screen native drawing includes layout, text measurement, formatting and
// rasterization. It does not measure physical display transfer or battery use.
function performanceBitmap() {
    return Graphics.createBufferedBitmap({
        :width=>246, :height=>106,
        :palette=>[Graphics.COLOR_BLACK,Graphics.COLOR_WHITE]
    }).get();
}

function performanceSetup(view, mode) {
    view.onTimerReset();
    view.isMetric=true;
    var info=Activity.getActivityInfo();
    for (var i=0;i<220;i++) {
        info.currentSpeed=3.0; info.altitude=100.0+0.3*i;
        info.elapsedTime=i*1000; info.timerState=Activity.TIMER_STATE_ON;
        info.totalAscent=i;
        view.compute(info);
    }
    if (mode==0) { view.onTimerPause(); }
}

// mode 0: unchanged paused page; 1: changing page; 2: compute only;
// 3: compute + draw; 4: 180-sample changing climb; 5: min == max window.
function performanceBatch(view, dc, mode, count) {
    var info=Activity.getActivityInfo();
    var start=System.getTimer();
    for (var i=0;i<count;i++) {
        if (mode>=2) {
            info.currentSpeed=3.0;
            info.altitude=166.0+0.15*i+0.35*Math.sin(i*0.07);
            info.elapsedTime=(220+i)*1000; info.timerState=Activity.TIMER_STATE_ON;
            info.totalAscent=66+i/7;
            view.compute(info);
        } else if (mode==1) {
            view.grade=0.03+(i%41)*0.0001; view.vam=600.0+i%99;
            view.distLight=12310.0+i*3; view.distSteep=2310.0+i;
            view.maxGrade=0.124; view.totalAscent=1286+i/7;
            view.quality=0.95+(i%5)*0.001;
        }
        if (mode<2 || mode==3) { view.onUpdate(dc); }
    }
    return System.getTimer()-start;
}

(:test)
function performanceAB(logger as Test.Logger) as Boolean {
    return runPerformanceComparison(logger,false);
}

(:test)
function performanceAA(logger as Test.Logger) as Boolean {
    return runPerformanceComparison(logger,true);
}

function runPerformanceComparison(logger as Test.Logger, identical as Boolean) as Boolean {
    logger.debug(identical ? "Comparison=A/A" : "Comparison=A/B");
    var bitmap=performanceBitmap(); var dc=bitmap.getDc();
    var counts=[500,500,1200,500,240,1200];
    for (var mode=0;mode<counts.size();mode++) {
        restoreTestProperties();
        Application.Properties.setValue("buffer_length",35);
        if (mode==4) {
            Application.Properties.setValue("buffer_fit_min",180);
            Application.Properties.setValue("buffer_fit_max",180);
        } else if (mode==5) {
            Application.Properties.setValue("buffer_fit_min",7);
            Application.Properties.setValue("buffer_fit_max",7);
        }
        var before=System.getSystemStats().usedMemory;
        var a=identical ? new GradeEstimatorView() : new ControlView();
        performanceSetup(a,mode); a.onUpdate(dc);
        var aMemory=System.getSystemStats().usedMemory-before;
        before=System.getSystemStats().usedMemory;
        var b=new GradeEstimatorView();
        performanceSetup(b,mode); b.onUpdate(dc);
        var bMemory=System.getSystemStats().usedMemory-before;
        logger.debug("MEM mode="+mode+" a="+aMemory+" b="+bMemory);
        // A newly loaded program exhibits several seconds of cold simulator
        // overhead. Warm both drawing paths before collecting the first pair.
        if (mode==0) {
            var warmUntil=System.getTimer()+30000;
            while (System.getTimer()<warmUntil) {
                performanceBatch(a,dc,mode,500);
                performanceBatch(b,dc,mode,500);
            }
        }
        performanceBatch(a,dc,mode,80); performanceBatch(b,dc,mode,80);
        for (var pair=0;pair<9;pair++) {
            performanceSetup(a,mode); performanceSetup(b,mode);
            var ta=0; var tb=0;
            if (pair%2==0) {
                ta=performanceBatch(a,dc,mode,counts[mode]);
                tb=performanceBatch(b,dc,mode,counts[mode]);
            } else {
                tb=performanceBatch(b,dc,mode,counts[mode]);
                ta=performanceBatch(a,dc,mode,counts[mode]);
            }
            logger.debug("PERF mode="+mode+" pair="+pair+" n="+counts[mode]+" a="+ta+" b="+tb);
        }
        a=null; b=null;
    }
    restoreTestProperties();
    return true;
}

(:test)
function referenceSampleParity(logger as Test.Logger) as Boolean {
    for (var config=0;config<4;config++) {
        restoreTestProperties();
        Application.Properties.setValue("buffer_length",35);
        if (config==1) {
            Application.Properties.setValue("buffer_fit_min",3);
            Application.Properties.setValue("buffer_fit_max",3);
        } else if (config==2) {
            Application.Properties.setValue("buffer_fit_min",7);
            Application.Properties.setValue("buffer_fit_max",180);
        } else if (config==3) {
            Application.Properties.setValue("buffer_fit_min",180);
            Application.Properties.setValue("buffer_fit_max",180);
        }
        var expected=new ReferenceView(); var actual=new GradeEstimatorView();
        var altitude=-600.0; var elapsed=0;
        for (var i=0;i<1800;i++) {
            var info=Activity.getActivityInfo();
            var slope=i%400<200 ? 0.035 : 0.08;
            altitude+=3.0*slope+0.07*Math.sin(i*0.53);
            elapsed+=i%103==0 ? 7000 : (i%59==0 ? 0 : 1000);
            info.currentSpeed=i%131==0 ? 0.0 : 3.0;
            info.altitude=i%149==0 ? null : altitude;
            info.elapsedTime=elapsed; info.totalAscent=i/3;
            info.timerState=i%173<4 ? Activity.TIMER_STATE_PAUSED : Activity.TIMER_STATE_ON;
            if (config==3 && i<500) {
                info.currentSpeed=3.0; info.altitude=altitude;
                info.elapsedTime=i*1000; info.timerState=Activity.TIMER_STATE_ON;
            }
            if (i%601==0) { expected.onTimerReset(); actual.onTimerReset(); }
            expected.compute(info); actual.compute(info);
            if (expected.grade!=actual.grade || expected.quality!=actual.quality ||
                expected.gradeWindowSize!=actual.gradeWindowSize || expected.vam!=actual.vam ||
                expected.distLight!=actual.distLight || expected.distSteep!=actual.distSteep ||
                expected.maxGrade!=actual.maxGrade || expected.totalAscent!=actual.totalAscent ||
                expected.calculating!=actual.calculating ||
                !expected.getStatusString().equals(actual.getStatusString())) {
                logger.error("Reference mismatch config="+config+" sample="+i);
                return false;
            }
        }
    }
    restoreTestProperties();
    return true;
}

// Follow-up workloads keep the original six timing boundaries unchanged.
// 6/7: frequently changing adaptive windows (7..20 / 7..180).
// 8: native FIT grade writes plus pauses/resumes. 9/10: precomputed inputs.
// 11: imperial tall drawing. 12: construction + cold first drawing.
// 13: changing dimensions and units, including the small-field fallback.
function changingAltitude(i) {
    var phase=i%240;
    var rise=phase<60 ? 0.09*phase : (phase<120 ? 5.4+0.6*(phase-60) :
        (phase<180 ? 41.4-0.3*(phase-120) : 23.4+0.03*(phase-180)));
    return 166.0+(i/240)*25.2+rise+0.45*Math.sin(i*0.91);
}

function preparedInputs(mode,count) {
    var rows=[];
    for (var i=0;i<count;i++) {
        rows.add([3.0,mode==9 ? 166.0+0.15*i+0.35*Math.sin(i*0.07) : changingAltitude(i),
            (220+i)*1000,66+i/7,Activity.TIMER_STATE_ON]);
    }
    return rows;
}

function extendedBatch(v,bitmaps,mode,count,inputs,control,identical) {
    var info=Activity.getActivityInfo();
    var start=System.getTimer();
    for (var i=0;i<count;i++) {
        if (mode<=10) {
            if (inputs!=null) {
                var row=inputs[i];
                info.currentSpeed=row[0]; info.altitude=row[1]; info.elapsedTime=row[2];
                info.totalAscent=row[3]; info.timerState=row[4];
            } else {
                info.currentSpeed=mode==8 && i%180>=165 ? 0.0 : 3.0;
                info.altitude=changingAltitude(i); info.elapsedTime=(220+i)*1000;
                info.totalAscent=66+i/7;
                info.timerState=mode==8 && i%180>=165 ? Activity.TIMER_STATE_PAUSED : Activity.TIMER_STATE_ON;
                if (mode==8 && i%180==165) { v.onTimerPause(); }
                if (mode==8 && i>0 && i%180==0) { v.onTimerResume(); }
            }
            v.compute(info);
        } else if (mode==12) {
            var cold=control && !identical ? new ControlView() : new GradeEstimatorView();
            cold.isMetric=i%2==0;
            cold.onUpdate(bitmaps[i%bitmaps.size()].getDc());
        } else {
            v.isMetric=mode==11 ? false : i%2==0;
            v.grade=0.03+(i%41)*0.0001; v.vam=600.0+i%99;
            v.distLight=12310.0+i*3; v.distSteep=2310.0+i;
            v.maxGrade=0.124; v.totalAscent=1286+i/7; v.quality=0.95+(i%5)*0.001;
            v.onUpdate(bitmaps[mode==11 ? 2 : i%bitmaps.size()].getDc());
        }
    }
    return System.getTimer()-start;
}

(:test)
function extendedPerformanceAB(logger as Test.Logger) as Boolean { return extendedComparison(logger,false,6,13); }
(:test)
function extendedPerformanceAA(logger as Test.Logger) as Boolean { return extendedComparison(logger,true,6,13); }

(:test)
function fitPerformanceAA(logger as Test.Logger) as Boolean { return extendedComparison(logger,true,8,8); }

function extendedComparison(logger,identical,firstMode,lastMode) {
    var bitmaps=[];
    var dimensions=[[246,78],[246,106],[246,160],[200,70]];
    for(var i=0;i<dimensions.size();i++) {
        bitmaps.add(Graphics.createBufferedBitmap({:width=>dimensions[i][0],:height=>dimensions[i][1],
            :palette=>[Graphics.COLOR_BLACK,Graphics.COLOR_WHITE]}).get());
    }
    for(var mode=firstMode;mode<=lastMode;mode++) {
        restoreTestProperties(); Application.Properties.setValue("buffer_length",35);
        if(mode==7 || mode==10) { Application.Properties.setValue("buffer_fit_max",180); }
        var a=identical ? new GradeEstimatorView() : new ControlView();
        var b=new GradeEstimatorView();
        if(mode==8) {
            // Register native fields after constructing the test views, as in
            // the native FIT regression fixtures.
            Application.Properties.setValue("enable_logging",true);
            Application.Properties.setValue("enable_grade_logging",true);
            a.initializeFields();
            // Both implementations write the same native stream sequentially.
            // The simulator rejects registering duplicate field IDs in one app.
            b.gradeField=a.gradeField; b.climbDistField=a.climbDistField;
            b.initializeFields();
        }
        if(mode==8 && (a.gradeField==null || b.gradeField==null || a.FIELD_SETUP_ERROR || b.FIELD_SETUP_ERROR)) {
            logger.error("Native FIT registration failed"); return false;
        }
        var count=mode<=8 ? 1200 : (mode<=10 ? 600 : (mode==12 ? 60 : 500));
        var inputs=mode==9 || mode==10 ? preparedInputs(mode,count) : null;
        performanceSetup(a,mode); performanceSetup(b,mode);
        var warmUntil=System.getTimer()+(mode==firstMode || mode==11 ? 30000 : 1000);
        while(System.getTimer()<warmUntil) {
            performanceSetup(a,mode); performanceSetup(b,mode);
            extendedBatch(a,bitmaps,mode,count,inputs,true,identical);
            extendedBatch(b,bitmaps,mode,count,inputs,false,identical);
        }
        for(var pair=0;pair<9;pair++) {
            performanceSetup(a,mode); performanceSetup(b,mode);
            var ta=0; var tb=0;
            if(pair%2==0) {
                ta=extendedBatch(a,bitmaps,mode,count,inputs,true,identical);
                tb=extendedBatch(b,bitmaps,mode,count,inputs,false,identical);
            } else {
                tb=extendedBatch(b,bitmaps,mode,count,inputs,false,identical);
                ta=extendedBatch(a,bitmaps,mode,count,inputs,true,identical);
            }
            logger.debug("PERF mode="+mode+" pair="+pair+" n="+count+" a="+ta+" b="+tb);
        }
        if(mode==8 && (a.FIELD_SETUP_ERROR || b.FIELD_SETUP_ERROR)) { return false; }
        a=null; b=null; inputs=null;
    }
    restoreTestProperties(); return true;
}

// Diagnostic only: not called by either timing entry point.
(:test)
function adaptiveWindowDiagnostics(logger as Test.Logger) as Boolean {
    for(var config=0;config<3;config++) {
        restoreTestProperties();
        Application.Properties.setValue("buffer_fit_max",config==2 ? 180 : 20);
        var v=new GradeEstimatorView(); performanceSetup(v,2);
        var histogram=[];
        for(var w=0;w<=180;w++) { histogram.add(0); }
        var unchanged=0; var grows=0; var shrinks=0;
        var info=Activity.getActivityInfo();
        for(var i=0;i<1200;i++) {
            var old=v.gradeWindowSize;
            info.currentSpeed=3.0;
            info.altitude=config==0 ? 166.0+0.15*i+0.35*Math.sin(i*0.07) : changingAltitude(i);
            info.elapsedTime=(220+i)*1000; info.timerState=Activity.TIMER_STATE_ON;
            v.compute(info);
            if(v.gradeWindowSize==old) { unchanged++; }
            else if(v.gradeWindowSize>old) { grows++; } else { shrinks++; }
            histogram[v.gradeWindowSize]++;
        }
        logger.debug("WINDOW config="+config+" max="+v.MAX_GRADE_WINDOW+" unchanged="+unchanged+" grows="+grows+" shrinks="+shrinks);
        for(var w=3;w<histogram.size();w++) {
            if(histogram[w]>0) { logger.debug("WINDOW count "+w+"="+histogram[w]); }
        }
    }
    restoreTestProperties(); return true;
}

(:test)
function adaptiveReferenceParity(logger as Test.Logger) as Boolean {
    for(var config=0;config<4;config++) {
        restoreTestProperties(); Application.Properties.setValue("buffer_length",35);
        Application.Properties.setValue("buffer_fit_max",config==0 ? 20 : 180);
        var expected=new ReferenceView(); var actual=new GradeEstimatorView();
        var info=Activity.getActivityInfo();
        for(var i=0;i<2400;i++) {
            info.currentSpeed=config==2 && i%180>=165 ? 0.0 : 3.0;
            info.altitude=config==3 ? 100.0+1.5*i+0.15*Math.sin(i*0.53) : changingAltitude(i); info.elapsedTime=i*1000;
            info.timerState=config==2 && i%180>=165 ? Activity.TIMER_STATE_PAUSED : Activity.TIMER_STATE_ON;
            info.totalAscent=i/7;
            if(config==2 && i%180==165) { expected.onTimerPause(); actual.onTimerPause(); }
            if(config==2 && i>0 && i%180==0) { expected.onTimerResume(); actual.onTimerResume(); }
            expected.compute(info); actual.compute(info);
            if(expected.grade!=actual.grade || expected.quality!=actual.quality ||
                expected.gradeWindowSize!=actual.gradeWindowSize || expected.vam!=actual.vam ||
                expected.distLight!=actual.distLight || expected.distSteep!=actual.distSteep ||
                expected.maxGrade!=actual.maxGrade || expected.totalAscent!=actual.totalAscent ||
                expected.calculating!=actual.calculating || !expected.getStatusString().equals(actual.getStatusString())) {
                logger.error("Adaptive reference mismatch config="+config+" sample="+i); return false;
            }
        }
    }
    restoreTestProperties(); return true;
}

(:test)
function allReferenceParity(logger as Test.Logger) as Boolean {
    return referenceSampleParity(logger) && adaptiveReferenceParity(logger);
}
