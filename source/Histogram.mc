import Toybox.Lang;

class Histogram {
    var minBin = -25.0; // Minimum value for bins
    //const maxBin = 25.0;  // Maximum value for bins
    var minQuality = 0.5; // Minimum quality to consider a data point
    
    private var bins as Array<Float> = [] as Array<Float>;
    private var binSize as Float;
    private var numBins as Number;
    private var totalCount as Float = 0.0;

    public var computed as Boolean = false;
    public var computedSampledBinRange as Array<Number> = [0, 0];
    public var computedHistogramForRange as Array<Float> = [];

    // One-second integration buckets keep memory bounded for arbitrarily long rides.
    // Held values are continuous moving averages, evaluated on this one-second grid.
    const windows = [10, 60, 300, 600, 900, 1200, 1800];
    private var history = new [1800];
    private var sums = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    private var best = [null, null, null, null, null, null, null];
    private var cursor = 0;
    private var continuousSeconds = 0;
    private var partialSeconds = 0.0;
    private var partialIntegral = 0.0;
    private var lastComputedSeconds = -1.0;

    public function shouldUpdate() as Boolean {
        var interval = totalCount < 100 ? 1 : (totalCount < 500 ? 2 : (totalCount < 2000 ? 4 : (totalCount < 5000 ? 8 : 16)));
        return totalCount - lastComputedSeconds >= interval;
    }

    // Keep completed session bests, but never join windows across missing/paused data.
    function breakSequence() {
        cursor = 0;
        continuousSeconds = 0;
        partialSeconds = 0.0;
        partialIntegral = 0.0;
        for (var i = 0; i < sums.size(); i++) { sums[i] = 0.0; }
    }

    private function addSecond(value as Float) {
        for (var i = 0; i < windows.size(); i++) {
            var seconds = windows[i];
            if (continuousSeconds >= seconds) {
                sums[i] -= history[(cursor + 1800 - seconds) % 1800];
            }
            sums[i] += value;
            if (continuousSeconds + 1 >= seconds) {
                var average = sums[i] / seconds;
                if (best[i] == null || average > best[i]) { best[i] = average; }
            }
        }
        history[cursor] = value;
        cursor = (cursor + 1) % 1800;
        if (continuousSeconds < 1800) { continuousSeconds++; }
    }

    function initialize(minQ as Float) {
        self.binSize = 1.0;
        self.minQuality = minQ;
        self.bins = [] as Array<Float>;
        for (var i = self.minBin; i < 25; i += binSize) { self.bins.add(0.0); }
        self.numBins = bins.size();
        self.totalCount = 0.0;
    }

    function addData(grade as Float, quality as Float) {
        addTimedData(grade, quality, 1.0);
    }

    function addTimedData(grade as Float, quality as Float, seconds as Float) {
        if (quality < minQuality || seconds <= 0.0) {
            breakSequence();
            return;
        }
        bins[getBinIndex(grade)] += seconds;
        totalCount += seconds;
        var remaining = seconds;
        while (remaining > 0.0) {
            var portion = 1.0 - partialSeconds;
            if (portion > remaining) { portion = remaining; }
            partialIntegral += grade * portion;
            partialSeconds += portion;
            remaining -= portion;
            if (partialSeconds >= 1.0) {
                addSecond(partialIntegral);
                partialSeconds = 0.0;
                partialIntegral = 0.0;
            }
        }
    }

    //! Get the bin index for a given grade value
    function getBinIndex(grade as Float) as Number {
        var binIndex = ((grade - self.minBin) / self.binSize).toNumber();
        if (binIndex < 0) { return 0; }
        if (binIndex >= self.numBins) { return self.numBins - 1; }
        return binIndex;
    }

    //! Get the central grade value for a given bin index
    function getGradeForBin(binIndex as Number) as Float {
        if (binIndex >= 0 && binIndex < self.numBins) {
            return self.minBin + binIndex * self.binSize + self.binSize / 2.0;
        }
        return 0.0;
    }

    //! Compute and store the histogram statistics
    function compute() {
        if (self.totalCount == 0) { return; }

        computedSampledBinRange = getSampledBinRange();

        if (computedSampledBinRange[0] > 21) { computedSampledBinRange[0] = 21; }
        if (computedSampledBinRange[1] < 28) { computedSampledBinRange[1] = 28; }

        computedHistogramForRange = getHistogramForRange(computedSampledBinRange);
        
        computed = true;
        lastComputedSeconds = totalCount;
    }

    private function getSampledBinRange() as Array {
        var minSampled = -1;
        var maxSampled = -1;
        for (var i = 0; i < self.numBins; i++) {
            if (self.bins[i] > 0) {
                if (minSampled == -1) { minSampled = i; }
                maxSampled = i;
            }
        }
        return [minSampled, maxSampled];
    }

    private function getHistogramForRange(range as Array) as Array {
        var result = new [0];
        for (var i = range[0]; i <= range[1]; i++) {
            result.add(self.bins[i].toFloat() / self.totalCount);
        }
        return result;
    }

    public function getHighGradeForTime(seconds as Float) as Float or Null {
        for (var i = 0; i < windows.size(); i++) {
            if (seconds == windows[i]) { return best[i]; }
        }
        return null;
    }

    public function getTrackedSeconds() as Float {
        return totalCount;
    }
}
