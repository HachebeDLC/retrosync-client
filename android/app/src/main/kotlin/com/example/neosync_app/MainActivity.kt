package com.example.neosync_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.Charset

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.neosync.app/launcher"
    private val PICK_DIRECTORY_REQUEST_CODE = 9999
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSafDirectoryPicker" -> openSafDirectoryPicker(call.argument<String>("initialUri"), result)
                "scanRecursive" -> scanRecursive(call.argument<String>("path")!!, call.argument<String>("systemId")!!, result)
                "calculateHash" -> calculateHash(call.argument<String>("path")!!, result)
                "calculateBlockHashes" -> calculateBlockHashes(call.argument<String>("path")!!, result)
                "uploadFileNative" -> {
                    val url = call.argument<String>("url")!!
                    val token = call.argument<String>("token")
                    val masterKey = call.argument<String>("masterKey")
                    val remotePath = call.argument<String>("remotePath")!!
                    val uri = call.argument<String>("uri")!!
                    val hash = call.argument<String>("hash")!!
                    val device = call.argument<String>("deviceName") ?: "Android"
                    val updated = (call.argument<Any>("updatedAt") as? Number)?.toLong() ?: 0L
                    val dirtyIndices = call.argument<List<Int>>("dirtyIndices")
                    uploadFileNative(url, token, masterKey, remotePath, uri, hash, device, updated, dirtyIndices, result)
                }
                "downloadFileNative" -> downloadFileNative(call.argument<String>("url")!!, call.argument<String>("token"), call.argument<String>("masterKey"), call.argument<String>("remoteFilename")!!, call.argument<String>("uri")!!, call.argument<String>("localFilename")!!, result)
                "getFileInfo" -> getFileInfo(call.argument<String>("uri")!!, result)
                "checkPathExists" -> result.success(checkPathExists(call.argument<String>("path")))
                "checkSafPermission" -> result.success(checkSafPermission(call.argument<String>("uri")!!))
                else -> result.notImplemented()
            }
        }
    }

    private fun checkSafPermission(uriStr: String): Boolean {
        if (!uriStr.startsWith("content://")) return true // Regular paths don't need SAF check here (targetSDK 29)
        val uri = Uri.parse(uriStr)
        val permissions = contentResolver.persistedUriPermissions
        for (p in permissions) {
            if (p.uri == uri && p.isWritePermission) return true
        }
        return false
    }

    private fun manualSkip(input: InputStream, n: Long): Long {
        var remaining = n
        val buffer = ByteArray(16384)
        while (remaining > 0) {
            val read = input.read(buffer, 0, Math.min(remaining, buffer.size.toLong()).toInt())
            if (read == -1) break
            remaining -= read
        }
        return n - remaining
    }

    private fun calculateBlockHashes(path: String, result: MethodChannel.Result) {
        Thread {
            try {
                val inputStream = if (path.startsWith("content://")) contentResolver.openInputStream(Uri.parse(path)) else File(path).inputStream()
                val blockHashes = JSONArray()
                val buffer = ByteArray(1024 * 1024)
                inputStream?.use { input ->
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        val digest = MessageDigest.getInstance("MD5")
                        digest.update(buffer, 0, read)
                        blockHashes.put(digest.digest().joinToString("") { "%02x".format(it) })
                    }
                }
                runOnUiThread { result.success(blockHashes.toString()) }
            } catch (e: Exception) { runOnUiThread { result.error("BLOCK_HASH_ERROR", e.message, null) } }
        }.start()
    }

    private fun uploadFileNative(url: String, token: String?, masterKey: String?, remotePath: String, uriStr: String, hash: String, deviceName: String, updatedAt: Long, dirtyIndices: List<Int>?, result: MethodChannel.Result) {
        Thread {
            try {
                val utf8 = Charsets.UTF_8
                val magic = "NEOSYNC".toByteArray(utf8)
                val keyBytes = if (masterKey != null) android.util.Base64.decode(masterKey, android.util.Base64.URL_SAFE).sliceArray(0 until 32) else null
                
                val plainSize = if (uriStr.startsWith("content://")) {
                    DocumentFile.fromSingleUri(this, Uri.parse(uriStr))?.length() ?: 0L
                } else File(uriStr).length()

                val blockSize = 1024 * 1024
                val totalBlocks = if (plainSize == 0L) 1 else ((plainSize + blockSize - 1) / blockSize).toInt()
                val indicesToSync = dirtyIndices ?: (0 until totalBlocks).toList()

                for (index in indicesToSync) {
                    val offset = index.toLong() * blockSize
                    val currentInputStream = if (uriStr.startsWith("content://")) contentResolver.openInputStream(Uri.parse(uriStr)) else File(uriStr).inputStream()
                    
                    currentInputStream?.use { input ->
                        if (offset > 0) {
                            val skipped = manualSkip(input, offset)
                            if (skipped < offset) throw Exception("Manual skip failed at block $index")
                        }
                        
                        val buffer = ByteArray(blockSize)
                        val bytesRead = if (plainSize > 0) input.read(buffer) else 0
                        
                        if (bytesRead != -1) {
                            val blockData = if (bytesRead == blockSize) buffer else if (bytesRead > 0) buffer.sliceArray(0 until bytesRead) else ByteArray(0)
                            val finalData: ByteArray = if (keyBytes != null && blockData.isNotEmpty()) {
                                val iv = MessageDigest.getInstance("MD5").digest(blockData)
                                val cipher = Cipher.getInstance("AES/CBC/PKCS7Padding").apply {
                                    init(Cipher.ENCRYPT_MODE, SecretKeySpec(keyBytes, "AES"), IvParameterSpec(iv))
                                }
                                val encrypted = cipher.doFinal(blockData)
                                val output = java.io.ByteArrayOutputStream()
                                output.write(magic); output.write(iv); output.write(encrypted)
                                output.toByteArray()
                            } else { blockData }

                            val connection = (java.net.URL(url).openConnection() as java.net.HttpURLConnection).apply {
                                requestMethod = "POST"
                                doOutput = true
                                setFixedLengthStreamingMode(finalData.size.toLong())
                                setRequestProperty("Content-Type", "application/octet-stream")
                                setRequestProperty("x-neosync-path", remotePath)
                                setRequestProperty("x-neosync-index", index.toString())
                                val encryptedBlockSize = if (keyBytes != null) 1048615 else 1048576
                                setRequestProperty("x-neosync-offset", (index.toLong() * encryptedBlockSize).toString())
                                if (token != null) setRequestProperty("Authorization", "Bearer $token")
                            }
                            connection.outputStream.use { it.write(finalData); it.flush() }
                            if (connection.responseCode != 200) throw Exception("Block $index: HTTP ${connection.responseCode}")
                            connection.disconnect()
                        }
                    }
                }

                val finalizeUrl = if (url.endsWith("/")) "${url}finalize" else "$url/finalize"
                val finalizeConn = (java.net.URL(finalizeUrl).openConnection() as java.net.HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    if (token != null) setRequestProperty("Authorization", "Bearer $token")
                }
                finalizeConn.outputStream.use { it.write(JSONObject().apply {
                    put("path", remotePath); put("hash", hash); put("size", plainSize); put("updated_at", updatedAt); put("device_name", deviceName)
                }.toString().toByteArray(utf8)) }
                if (finalizeConn.responseCode != 200) throw Exception("Finalization failed")
                finalizeConn.disconnect()

                runOnUiThread { result.success(true) }
            } catch (e: Exception) { runOnUiThread { result.error("UPLOAD_ERROR", e.message, null) } }
        }.start()
    }

    private fun downloadFileNative(url: String, token: String?, masterKey: String?, remoteFilename: String, uriStr: String, localFilename: String, result: MethodChannel.Result) {
        Thread {
            var connection: java.net.HttpURLConnection? = null
            var output: OutputStream? = null
            try {
                val utf8 = Charsets.UTF_8
                val magic = "NEOSYNC".toByteArray(utf8)
                val keyBytes = if (masterKey != null) android.util.Base64.decode(masterKey, android.util.Base64.URL_SAFE).sliceArray(0 until 32) else null

                val urlObj = java.net.URL(url)
                connection = (urlObj.openConnection() as java.net.HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Accept-Encoding", "identity")
                    if (token != null) setRequestProperty("Authorization", "Bearer $token")
                }
                
                connection.outputStream.use { it.write(JSONObject().put("filename", remoteFilename).toString().toByteArray(utf8)) }
                if (connection.responseCode != 200) throw Exception("Download failed: HTTP ${connection.responseCode}")

                output = if (uriStr.startsWith("content://")) {
                    val root = DocumentFile.fromTreeUri(this, Uri.parse(uriStr))!!
                    val parts = localFilename.split("/")
                    var dir = root
                    for (i in 0 until parts.size - 1) { 
                        if (parts[i].isEmpty()) continue
                        dir = dir.findFile(parts[i]) ?: dir.createDirectory(parts[i])!! 
                    }
                    val target = dir.findFile(parts.last()) ?: dir.createFile("application/octet-stream", parts.last())!!
                    contentResolver.openOutputStream(target.uri, "wt")
                } else {
                    val f = File(File(uriStr), localFilename)
                    if (!f.parentFile.exists()) f.parentFile.mkdirs()
                    f.outputStream()
                }

                connection!!.inputStream.use { input ->
                    if (keyBytes != null) {
                        val buffer = java.io.ByteArrayOutputStream()
                        val chunk = ByteArray(65536)
                        val encryptedBlockSize = 1048615
                        while (true) {
                            val r = input.read(chunk)
                            if (r == -1) break
                            buffer.write(chunk, 0, r)
                            val data = buffer.toByteArray()
                            if (data.size >= encryptedBlockSize) {
                                val block = data.sliceArray(0 until encryptedBlockSize)
                                if (block.sliceArray(0..6).contentEquals(magic)) {
                                    val iv = block.sliceArray(7..22)
                                    val encrypted = block.sliceArray(23 until encryptedBlockSize)
                                    val cipher = Cipher.getInstance("AES/CBC/PKCS7Padding").apply {
                                        init(Cipher.DECRYPT_MODE, SecretKeySpec(keyBytes, "AES"), IvParameterSpec(iv))
                                    }
                                    output?.write(cipher.doFinal(encrypted))
                                }
                                buffer.reset(); buffer.write(data, encryptedBlockSize, data.size - encryptedBlockSize)
                            }
                        }
                        val last = buffer.toByteArray()
                        if (last.size > 23 && last.sliceArray(0..6).contentEquals(magic)) {
                            val iv = last.sliceArray(7..22); val enc = last.sliceArray(23 until last.size)
                            val cipher = Cipher.getInstance("AES/CBC/PKCS7Padding").apply {
                                init(Cipher.DECRYPT_MODE, SecretKeySpec(keyBytes, "AES"), IvParameterSpec(iv))
                            }
                            output?.write(cipher.doFinal(enc))
                        }
                    } else {
                        input.copyTo(output!!)
                    }
                }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) { runOnUiThread { result.error("DOWNLOAD_ERROR", e.message, null) } }
            finally { try { output?.close() } catch(e: Exception) {}; try { connection?.errorStream?.close() } catch(e: Exception) {}; connection?.disconnect() }
        }.start()
    }

    private fun calculateHash(path: String, result: MethodChannel.Result) {
        Thread {
            try {
                val input = if (path.startsWith("content://")) contentResolver.openInputStream(Uri.parse(path)) else File(path).inputStream()
                val digest = MessageDigest.getInstance("MD5")
                input?.use { stream ->
                    val buffer = ByteArray(65536)
                    var read: Int
                    while (stream.read(buffer).also { read = it } != -1) { digest.update(buffer, 0, read) }
                }
                runOnUiThread { result.success(digest.digest().joinToString("") { "%02x".format(it) }) }
            } catch (e: Exception) { runOnUiThread { result.error("HASH_ERROR", e.message, null) } }
        }.start()
    }

    private fun scanRecursive(path: String, systemId: String, result: MethodChannel.Result) {
        Thread {
            try {
                val results = JSONArray()
                val allowedExts = setOf("srm", "save", "sav", "state", "ps2", "mcd", "dat", "nvmem", "eep", "vms", "vmu", "png")
                fun isAllowedFile(name: String) = allowedExts.contains(name.split(".").last().lowercase()) || name.endsWith(".state.auto")
                if (path.startsWith("content://")) {
                    val rootUri = Uri.parse(path)
                    val treeId = try { DocumentsContract.getTreeDocumentId(rootUri) } catch(e: Exception) { null }
                    if (treeId != null) {
                        fun walkSaf(currentDocId: String, currentRelPath: String) {
                            contentResolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(rootUri, currentDocId), arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED), null, null, null)?.use { cursor ->
                                while (cursor.moveToNext()) {
                                    val id = cursor.getString(0); val name = cursor.getString(1) ?: "unknown"
                                    val relPath = if (currentRelPath.isEmpty()) name else "$currentRelPath/$name"
                                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) walkSaf(id, relPath)
                                    else if (isAllowedFile(name)) results.put(JSONObject().apply { put("name", name); put("relPath", relPath); put("uri", DocumentsContract.buildDocumentUriUsingTree(rootUri, id).toString()); put("size", cursor.getLong(3)); put("lastModified", cursor.getLong(4)) })
                                }
                            }
                        }
                        walkSaf(treeId, "")
                    }
                } else {
                    fun walkLocal(dir: File, currentRelPath: String) {
                        dir.listFiles()?.forEach { file ->
                            val relPath = if (currentRelPath.isEmpty()) file.name else "$currentRelPath/${file.name}"
                            if (file.isDirectory) walkLocal(file, relPath)
                            else if (isAllowedFile(file.name)) results.put(JSONObject().apply { put("name", file.name); put("relPath", relPath); put("uri", file.absolutePath); put("size", file.length()); put("lastModified", file.lastModified()) })
                        }
                    }
                    walkLocal(File(path), "")
                }
                runOnUiThread { result.success(results.toString()) }
            } catch (e: Exception) { runOnUiThread { result.error("SCAN_ERROR", e.message, null) } }
        }.start()
    }

    private fun getFileInfo(uriStr: String, result: MethodChannel.Result) {
        Thread {
            try {
                val f = if (uriStr.startsWith("content://")) DocumentFile.fromSingleUri(this, Uri.parse(uriStr)) else DocumentFile.fromFile(File(uriStr))
                if (f != null && f.exists()) runOnUiThread { result.success(mapOf("size" to f.length(), "lastModified" to f.lastModified())) }
                else runOnUiThread { result.error("NOT_FOUND", "File not found", null) }
            } catch (e: Exception) { runOnUiThread { result.error("INFO_ERROR", e.message, null) } }
        }.start()
    }

    private fun checkPathExists(path: String?): Boolean {
        if (path == null) return false
        return if (path.startsWith("content://")) {
            try { DocumentFile.fromTreeUri(this, Uri.parse(path))?.exists() ?: false } catch (e: Exception) { false }
        } else File(path).exists()
    }

    private fun openSafDirectoryPicker(initialUriStr: String?, result: MethodChannel.Result) {
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && initialUriStr != null) {
            intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initialUriStr))
        }
        startActivityForResult(intent, PICK_DIRECTORY_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_DIRECTORY_REQUEST_CODE && resultCode == Activity.RESULT_OK) {
            data?.data?.let { uri ->
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                pendingResult?.success(uri.toString())
            } ?: pendingResult?.success(null)
            pendingResult = null
        }
    }
}
