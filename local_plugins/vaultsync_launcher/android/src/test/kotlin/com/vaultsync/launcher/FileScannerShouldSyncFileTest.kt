package com.vaultsync.launcher

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [FileScanner.shouldSyncFile], the pure save-filter helper.
 *
 * Regression coverage for the "N directories, 0 files" Switch bug: the scan
 * walk constrains traversal to the nand/user/save subtree, so every file that
 * reaches shouldSyncFile is already a genuine save. The filter must therefore
 * sync everything for switch/eden — it must NOT additionally require the title
 * ID prefix "0100" in the path, because Ryujinx-style and older Yuzu layouts
 * key saves by save-data ID (not title ID) and never put "0100" in the path.
 *
 * Must stay in parity with the Dart `DartFileScanner.shouldSyncFile`
 * (`_syncEverythingSids` → return true).
 */
class FileScannerShouldSyncFileTest {

    @Test
    fun `switch syncs save with title id in path (yuzu layout)`() {
        assertTrue(
            FileScanner.shouldSyncFile(
                "switch",
                "nand/user/save/0000000000000000/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/0100a66006f76000/file",
                "file"
            )
        )
    }

    @Test
    fun `switch syncs save without title id in path (ryujinx save-data-id layout)`() {
        // No "0100" anywhere — this is the case that previously yielded 0 files.
        assertTrue(
            FileScanner.shouldSyncFile(
                "switch",
                "nand/user/save/0000000000000008/0000000000000001/Data",
                "Data"
            )
        )
    }

    @Test
    fun `switch syncs extensionless binary save blob`() {
        assertTrue(FileScanner.shouldSyncFile("switch", "save/8/0/imkvdb.arc", "imkvdb.arc"))
    }

    @Test
    fun `eden behaves like switch`() {
        assertTrue(
            FileScanner.shouldSyncFile("eden", "nand/user/save/abc/def/somesave", "somesave")
        )
    }

    @Test
    fun `switch still rejects dotfiles and bak rotations`() {
        assertFalse(FileScanner.shouldSyncFile("switch", "save/.hidden", ".hidden"))
        assertFalse(FileScanner.shouldSyncFile("switch", "save/foo.bak", "foo.bak"))
    }
}
