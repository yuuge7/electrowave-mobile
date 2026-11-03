package com.example.electrowave_mobile

import java.io.File
import java.io.RandomAccessFile
import java.io.ByteArrayOutputStream

/** FLAC verbatim frames: preserves 24-bit PCM without a second lossy encode.
 * Used only for derived playback files; the source file is never opened for write.
 * FLAC bitstream specification: RFC 9639, STREAMINFO and verbatim subframes.
 */
class PcmFlacWriter(file:File,private val rate:Int) {
    private val out=RandomAccessFile(file,"rw")
    private val left=IntArray(4096);private val right=IntArray(4096)
    private var count=0;private var frame=0;private var total=0L
    init {out.setLength(0);out.write("fLaC".toByteArray());out.write(byteArrayOf(0x80.toByte(),0,0,34));out.write(ByteArray(34))}
    private fun crc(bytes:ByteArray,bits:Int,polynomial:Int):Int {
        var crc=0;val mask=(1 shl bits)-1
        for(b in bytes) {crc=crc xor ((b.toInt() and 255) shl (bits-8));repeat(8){crc=if(crc and (1 shl (bits-1))!=0) ((crc shl 1) xor polynomial) and mask else (crc shl 1) and mask}}
        return crc
    }
    private fun number(value:Int):ByteArray {
        if(value<128) return byteArrayOf(value.toByte())
        var n=2;while(n<6 && value >= (1L shl (5*n+1))) n++
        val bytes=ByteArray(n);var remaining=value
        for(i in n-1 downTo 1){bytes[i]=(0x80 or (remaining and 63)).toByte();remaining=remaining ushr 6}
        bytes[0]=(((0xff shl (8-n)) and 255) or remaining).toByte();return bytes
    }
    fun add(l:Double,r:Double) {
        left[count]=(l*8388608.0).toLong().coerceIn(-8388608,8388607).toInt()
        right[count]=(r*8388608.0).toLong().coerceIn(-8388608,8388607).toInt()
        count++;total++;if(count==4096) flush()
    }
    private fun flush() {
        if(count==0) return
        val header=ByteArrayOutputStream();header.write(byteArrayOf(0xff.toByte(),0xf8.toByte(),0x70,0x1c));header.write(number(frame++))
        header.write((count-1) shr 8);header.write((count-1) and 255)
        val block=ByteArrayOutputStream();val h=header.toByteArray();block.write(h);block.write(crc(h,8,0x07))
        for(samples in arrayOf(left,right)) {block.write(2);for(i in 0 until count){val s=samples[i];block.write((s shr 16) and 255);block.write((s shr 8) and 255);block.write(s and 255)}}
        val bytes=block.toByteArray();out.write(bytes);val checksum=crc(bytes,16,0x8005);out.write(checksum shr 8);out.write(checksum and 255);count=0
        check(out.length()<=512L*1024*1024) {"Derived audio exceeds the 512 MB working limit"}
    }
    fun close() {
        try {
            flush();out.seek(8);out.writeShort(16);out.writeShort(4096);out.write(ByteArray(6))
            val info=(rate.toLong() shl 44) or (1L shl 41) or (23L shl 36) or (total and 0xfffffffffL)
            out.writeLong(info);out.write(ByteArray(16))
        } finally {out.close()}
    }
}
