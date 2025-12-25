import Foundation

private let HISTORY_SIZE: Int = 20
private let ASSUME_POINTER_MOVE_STOPPED_MILLIS: Int = 40
private let HORIZON_MILLIS: Int = 100

final class VelocityTracker {
    private var mTimeSamples: [Int] = Array(repeating: Int.min, count: HISTORY_SIZE)
    private var mDataSamples: [Float] = Array(repeating: 0.0, count: HISTORY_SIZE)
    private var mIndex: Int = 0
    
    init() {
        for i in 0..<HISTORY_SIZE {
            mTimeSamples[i] = Int.min
        }
    }
    
    func addDataPoint(_ timeMillis: Int, _ data: Float) {
        mIndex = (mIndex + 1) % HISTORY_SIZE
        mTimeSamples[mIndex] = timeMillis
        mDataSamples[mIndex] = data
    }
    
    func resetTracking() {
        mIndex = 0
        for i in 0..<HISTORY_SIZE {
            mTimeSamples[i] = Int.min
        }
        for i in 0..<HISTORY_SIZE {
            mDataSamples[i] = 0.0
        }
    }
    
    func calculateVelocity() -> Float {
        var sampleCount = 0
        var index = mIndex
        
        if index == 0 && mTimeSamples[index] == Int.min {
            return 0.0
        }
        
        let newestTime = mTimeSamples[index]
        var previousTime = newestTime
        
        repeat {
            let sampleTime = mTimeSamples[index]
            if sampleTime == Int.min {
                break
            }
            let age: Float = Float(newestTime - sampleTime)
            let delta: Float = Float(abs(sampleTime - previousTime))
            previousTime = sampleTime
            
            if age > Float(HORIZON_MILLIS) || delta > Float(ASSUME_POINTER_MOVE_STOPPED_MILLIS) {
                break
            }
            
            index = (index == 0 ? HISTORY_SIZE : index) - 1
            sampleCount += 1
        } while (sampleCount < HISTORY_SIZE)
        
        if sampleCount < 2 {
            return 0.0
        }
        
        if sampleCount == 2 {
            let prevIndex = (mIndex == 0 ? HISTORY_SIZE - 1 : mIndex - 1)
            let timeDiff: Float = Float(mTimeSamples[mIndex] - mTimeSamples[prevIndex])
            if timeDiff == 0.0 {
                return 0.0
            }
            let dataDiff: Float = mDataSamples[mIndex] - mDataSamples[prevIndex]
            return dataDiff / timeDiff * 1000.0
        }
        
        var work: Float = 0.0
        let startIndex = (mIndex - sampleCount + HISTORY_SIZE + 1) % HISTORY_SIZE
        let endIndex = (mIndex + 1 + HISTORY_SIZE) % HISTORY_SIZE
        previousTime = mTimeSamples[startIndex]
        var previousData: Float = mDataSamples[startIndex]
        var i = (startIndex + 1) % HISTORY_SIZE
        while i != endIndex {
            let time = mTimeSamples[i]
            let timeDelta = time - previousTime
            if timeDelta == 0 {
                i = (i + 1) % HISTORY_SIZE
                continue
            }
            let data = mDataSamples[i]
            let vPrev = kineticEnergyToVelocity(work)
            let dataPointsDelta: Float = data - previousData
            
            let vCurr: Float = dataPointsDelta / Float(timeDelta)
            work += (vCurr - vPrev) * abs(vCurr)
            if i == startIndex + 1 {
                work = (work * 0.5)
            }
            previousTime = time
            previousData = data
            
            i = (i + 1) % HISTORY_SIZE
        }
        return kineticEnergyToVelocity(work) * 1000.0
    }
    
    private func kineticEnergyToVelocity(_ kineticEnergy: Float) -> Float {
        let s: Float = kineticEnergy > 0 ? 1.0 : (kineticEnergy < 0 ? -1.0 : 0.0)
        return Float(s * Float(sqrt(2.0 * Double(abs(kineticEnergy)))))
    }
}
