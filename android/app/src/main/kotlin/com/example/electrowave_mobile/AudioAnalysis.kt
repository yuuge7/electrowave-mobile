package com.example.electrowave_mobile

import android.media.*
import java.nio.ByteOrder
import java.io.File
import java.security.MessageDigest
import kotlin.math.*

/** Streaming PCM analysis: bounded waveform and BS.1770 K-weighted,
 * absolute/relative-gated loudness for ReplayGain 2.0 (-18 LUFS).
 * Filter equations: ITU BS.1770; constants cross-checked with libebur128.
 */
object AudioAnalysis {
    private class Biquad(val b: DoubleArray, val a: DoubleArray) {
        var x1=0.0; var x2=0.0; var y1=0.0; var y2=0.0
        fun process(x:Double):Double {
            val y=b[0]*x+b[1]*x1+b[2]*x2-a[1]*y1-a[2]*y2
            x2=x1;x1=x;y2=y1;y1=y;return y
        }
    }
    private fun filters(rate:Int):Pair<Biquad,Biquad> {
        val k=tan(PI*1681.974450955533/rate);val q=0.7071752369554196
        val vh=10.0.pow(3.999843853973347/20);val vb=vh.pow(0.4996667741545416)
        val d=1+k/q+k*k
        val shelf=Biquad(doubleArrayOf((vh+vb*k/q+k*k)/d,2*(k*k-vh)/d,(vh-vb*k/q+k*k)/d),
            doubleArrayOf(1.0,2*(k*k-1)/d,(1-k/q+k*k)/d))
        val h=tan(PI*38.13547087602444/rate);val hq=0.5003270373238773;val hd=1+h/hq+h*h
        return shelf to Biquad(doubleArrayOf(1.0,-2.0,1.0),doubleArrayOf(1.0,2*(h*h-1)/hd,(1-h/hq+h*h)/hd))
    }
    fun crossfeed(path:String,cache:File,mix:Boolean=true):String {
        cache.mkdirs()
        val source=File(path)
        val key=MessageDigest.getInstance("SHA-256").digest((path+":"+mix+":"+source.length()+":"+source.lastModified()).toByteArray()).joinToString(""){"%02x".format(it)}
        val output=File(cache,"$key.flac")
        if(output.exists()) {output.setLastModified(System.currentTimeMillis());return output.path}
        val temporary=File(cache,"$key.tmp")
        try {analyze(path,temporary,mix);check(temporary.renameTo(output)) {"Could not save crossfeed cache"}}
        finally {temporary.delete()}
        // Keep a small working set. It contains derived audio only.
        cache.listFiles()?.filter{it.extension=="flac"}?.sortedByDescending{it.lastModified()}?.drop(5)?.forEach{it.delete()}
        return output.path
    }
    fun analyze(path:String,render:File?=null,mix:Boolean=true):Map<String,Any> {
        val extractor=MediaExtractor();var codec:MediaCodec?=null
        var rendered:PcmFlacWriter?=null
        var lowLeft=0.0;var lowRight=0.0
        try {
            extractor.setDataSource(path)
            val index=(0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/")==true }
                ?: error("No audio stream")
            extractor.selectTrack(index);val format=extractor.getTrackFormat(index)
            val duration=if(format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            require(duration>0 && duration<=86_400_000_000L) { "Audio duration unavailable or exceeds 24 hours" }
            val decoder=MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!);codec=decoder
            decoder.configure(format,null,null,0);decoder.start()
            var channels=format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);var rate=format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var encoding=AudioFormat.ENCODING_PCM_16BIT
            var bank=Array(channels){filters(rate)}
            val peaks=DoubleArray(256);var peak=0.0
            val blocks=ArrayList<Double>();var sum=0.0;var frames=0;var blockFrames=max(1,rate/10)
            var inputDone=false;var outputDone=false;val info=MediaCodec.BufferInfo()
            var lastOutput=System.currentTimeMillis()
            while(!outputDone) {
                check(System.currentTimeMillis()-lastOutput<30_000) { "Decoder timed out" }
                if(!inputDone) {
                    val i=decoder.dequeueInputBuffer(10_000)
                    if(i>=0) {
                        val buffer=decoder.getInputBuffer(i)!!;val size=extractor.readSampleData(buffer,0)
                        if(size<0) { decoder.queueInputBuffer(i,0,0,0,MediaCodec.BUFFER_FLAG_END_OF_STREAM);inputDone=true }
                        else { decoder.queueInputBuffer(i,0,size,extractor.sampleTime,0);extractor.advance() }
                    }
                }
                val i=decoder.dequeueOutputBuffer(info,10_000)
                if(i==MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val out=decoder.outputFormat
                    channels=out.getInteger(MediaFormat.KEY_CHANNEL_COUNT);rate=out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    require(channels in 1..8) { "Unsupported channel count" }
                    encoding=if(out.containsKey(MediaFormat.KEY_PCM_ENCODING)) out.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                    bank=Array(channels){filters(rate)};blockFrames=max(1,rate/10)
                } else if(i>=0) {
                    lastOutput=System.currentTimeMillis()
                    val buffer=decoder.getOutputBuffer(i)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buffer.position(info.offset);buffer.limit(info.offset+info.size)
                    val width=when(encoding){AudioFormat.ENCODING_PCM_FLOAT,22->4;21->3;AudioFormat.ENCODING_PCM_8BIT->1;else->2}
                    var frameIndex=0
                    if(render!=null && rendered==null) rendered=PcmFlacWriter(render,rate)
                    val alpha=1-exp(-2*PI*700/rate)
                    while(buffer.remaining()>=channels*width) {
                        var energy=0.0;var amplitude=0.0;var left=0.0;var right=0.0
                        for(ch in 0 until channels) {
                            val x=when(encoding) {
                                AudioFormat.ENCODING_PCM_FLOAT->buffer.float.toDouble()
                                22->buffer.int/2147483648.0
                                21->{val v=(buffer.get().toInt() and 255) or ((buffer.get().toInt() and 255) shl 8) or (buffer.get().toInt() shl 16);v/8388608.0}
                                AudioFormat.ENCODING_PCM_8BIT->((buffer.get().toInt() and 255)-128)/128.0
                                else->buffer.short/32768.0
                            }
                            if(ch==0) left=x;if(ch==1) right=x
                            if(x.isFinite()) {
                                peak=max(peak,abs(x));amplitude=max(amplitude,abs(x))
                                val y=bank[ch].second.process(bank[ch].first.process(x))
                                val weight=if(channels>=6 && ch==3) 0.0 else if(ch>=4 || (channels in 4..5 && ch>=channels-2)) 1.41 else 1.0
                                energy+=y*y*weight
                            }
                        }
                        if(rendered!=null) {
                            if(channels==1) right=left
                            lowLeft+=alpha*(left-lowLeft);lowRight+=alpha*(right-lowRight)
                            rendered.add(if(mix) (left+0.3*lowRight)/1.3 else left,if(mix) (right+0.3*lowLeft)/1.3 else right)
                        }
                        val at=info.presentationTimeUs+frameIndex*1_000_000L/rate
                        val bucket=(at*256/duration).toInt().coerceIn(0,255)
                        peaks[bucket]=max(peaks[bucket],amplitude)
                        sum+=energy;frames++;frameIndex++
                        if(frames>=blockFrames) {blocks.add(sum/frames);sum=0.0;frames=0}
                    }
                    outputDone=info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    decoder.releaseOutputBuffer(i,false)
                }
            }
            if(frames>0) blocks.add(sum/frames)
            val windows=if(blocks.size<4) listOf(blocks.average()) else (0..blocks.size-4).map { n -> (blocks[n]+blocks[n+1]+blocks[n+2]+blocks[n+3])/4 }
            fun lufs(e:Double)=-0.691+10*log10(max(e,1e-12))
            val absolute=windows.filter { lufs(it)> -70 }
            val threshold=if(absolute.isEmpty()) -70.0 else lufs(absolute.average())-10
            val gated=absolute.filter{lufs(it)>=threshold}
            val loudness=if(gated.isEmpty()) -70.0 else lufs(gated.average())
            val gain=if(peak<1e-8) 0.0 else min(-18-loudness,-20*log10(peak)).coerceIn(-30.0,20.0)
            return mapOf("waveform" to peaks.toList(),"gainDb" to gain,"lufs" to loudness,"peak" to peak)
        } finally {
            try {rendered?.close()} finally {
                try {codec?.stop()} catch(_:Exception){};codec?.release();extractor.release()
            }
        }
    }
}
