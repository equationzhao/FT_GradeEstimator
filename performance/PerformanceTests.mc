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
        var a=new ControlView();
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
