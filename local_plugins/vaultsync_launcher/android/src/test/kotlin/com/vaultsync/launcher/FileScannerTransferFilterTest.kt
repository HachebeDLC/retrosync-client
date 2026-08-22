package com.vaultsync.launcher

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Parity counterpart of the Dart transfer_filters_test.dart.
 *
 * The two scanners must agree: the native one runs on Android, the Dart one on
 * desktop and as a fallback. They had already drifted once (the Dart global
 * extension set was missing "bak" and "psu"), so these rules are pinned on both
 * sides rather than only declared in a comment.
 */
class FileScannerTransferFilterTest {

    @Test
    fun `rejects VaultSync partial-transfer files`() {
        assertFalse(
            FileScanner.shouldSyncFile("ps2", "memcards/STAGEDAT.PDT.vstmp", "STAGEDAT.PDT.vstmp")
        )
    }

    @Test
    fun `rejects vstmp even for sync-everything systems`() {
        assertFalse(
            FileScanner.shouldSyncFile("switch", "nand/user/save/x/y/save.dat.vstmp", "save.dat.vstmp")
        )
    }

    @Test
    fun `rejects files inside a hidden directory`() {
        assertFalse(
            FileScanner.shouldSyncFile(
                "ps2", ".stversions/Mcd002~20231230-160750.ps2", "Mcd002~20231230-160750.ps2"
            )
        )
    }

    @Test
    fun `rejects a hidden directory nested deeper in the path`() {
        assertFalse(FileScanner.shouldSyncFile("ps2", "memcards/.stversions/Mcd001.ps2", "Mcd001.ps2"))
    }

    @Test
    fun `rejects hidden dirs for sync-everything systems too`() {
        assertFalse(FileScanner.shouldSyncFile("switch", "nand/.trash/0100F2C0115B6000/x.dat", "x.dat"))
    }

    @Test
    fun `still accepts a normal save`() {
        assertTrue(FileScanner.shouldSyncFile("ps2", "memcards/Mcd001.ps2", "Mcd001.ps2"))
    }

    @Test
    fun `hasHiddenSegment ignores the trailing file component`() {
        assertFalse(FileScanner.hasHiddenSegment("memcards/Mcd001.ps2"))
        assertTrue(FileScanner.hasHiddenSegment(".stversions/Mcd001.ps2"))
        assertTrue(FileScanner.hasHiddenSegment("a/.b/c.ps2"))
    }
}
