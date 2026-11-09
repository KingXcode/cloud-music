package dev.cloudmusic.cloud_music

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

class UpdatePackagePolicyTest {
    private lateinit var root: File
    private lateinit var cache: File

    @Before
    fun createCache() {
        root = Files.createTempDirectory("cloud-music-updates-test").toFile().canonicalFile
        cache = File(root, "app_updates").apply { mkdir() }
    }

    @After
    fun removeCache() {
        root.deleteRecursively()
    }

    @Test
    fun acceptsCompletedApkInExactCache() {
        val apk = File(cache, "update-test.apk").apply { writeText("test archive") }
        assertEquals(apk, UpdatePackagePolicy.validateFile(apk.path, cache))
    }

    @Test
    fun rejectsOutsideFilesAndSiblingPrefix() {
        val outside = File(root, "update.apk").apply { writeText("outside") }
        assertInvalidFile(outside.path)
        val sibling = File(root, "app_updates_other").apply { mkdir() }
        assertInvalidFile(File(sibling, "update.apk").apply { writeText("outside") }.path)
    }

    @Test
    fun rejectsNestedFilesAndTraversal() {
        val nested = File(cache, "nested").apply { mkdir() }
        assertInvalidFile(File(nested, "update.apk").apply { writeText("nested") }.path)
        File(cache, "update.apk").writeText("update")
        assertInvalidFile("${nested.path}/../update.apk")
    }

    @Test
    fun rejectsSymlinkEvenWhenItPointsIntoCache() {
        val apk = File(cache, "update.apk").apply { writeText("real") }
        val link = File(cache, "link.apk")
        Files.createSymbolicLink(link.toPath(), apk.toPath())
        assertInvalidFile(link.path)
    }

    @Test
    fun rejectsEmptyPartialMissingAndRelativeFiles() {
        assertInvalidFile(File(cache, "empty.apk").apply { createNewFile() }.path)
        assertInvalidFile(File(cache, "update.apk.part").apply { writeText("partial") }.path)
        assertInvalidFile(File(cache, "missing.apk").path)
        assertInvalidFile("update.apk")
        assertInvalidFile(File(cache, "directory.apk").apply { mkdir() }.path)
    }

    @Test
    fun acceptsNewerSamePackageAndExactSigningSet() {
        validate(candidateVersion = 2)
        validate(installedSigners = setOf("a", "b"), candidateSigners = setOf("b", "a"))
    }

    @Test
    fun rejectsDifferentPackage() {
        assertFailure("package_mismatch") { validate(candidatePackage = "another.app") }
    }

    @Test
    fun rejectsSameVersionAndDowngradeIncludingLongBuildCodes() {
        assertFailure("version_not_newer") { validate(candidateVersion = 1) }
        assertFailure("version_not_newer") { validate(candidateVersion = 0) }
        assertFailure("version_not_newer") {
            validate(installedVersion = Int.MAX_VALUE.toLong() + 4, candidateVersion = 2)
        }
    }

    @Test
    fun rejectsMissingMismatchedAndPartiallyOverlappingSigners() {
        assertFailure("signature_mismatch") { validate(installedSigners = emptySet()) }
        assertFailure("signature_mismatch") { validate(candidateSigners = emptySet()) }
        assertFailure("signature_mismatch") { validate(candidateSigners = setOf("other")) }
        assertFailure("signature_mismatch") {
            validate(installedSigners = setOf("a", "b"), candidateSigners = setOf("a"))
        }
    }

    private fun assertInvalidFile(path: String) = assertFailure("invalid_package") {
        UpdatePackagePolicy.validateFile(path, cache)
    }

    private fun assertFailure(code: String, action: () -> Unit) {
        val failure = assertThrows(UpdateFailure::class.java) { action() }
        assertEquals(code, failure.code)
    }

    private fun validate(
        candidatePackage: String = "dev.cloudmusic.cloud_music",
        installedVersion: Long = 1,
        candidateVersion: Long = 2,
        installedSigners: Set<String> = setOf("a"),
        candidateSigners: Set<String> = setOf("a"),
    ) = UpdatePackagePolicy.validateIdentity(
        installedPackage = "dev.cloudmusic.cloud_music",
        candidatePackage = candidatePackage,
        installedVersion = installedVersion,
        candidateVersion = candidateVersion,
        installedSigners = installedSigners,
        candidateSigners = candidateSigners,
    )
}
