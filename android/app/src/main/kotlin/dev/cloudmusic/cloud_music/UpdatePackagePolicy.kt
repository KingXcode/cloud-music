package dev.cloudmusic.cloud_music

import java.io.File

internal class UpdateFailure(val code: String, override val message: String) : Exception(message)

/** Pure checks shared by the native installer bridge and its JVM regression tests. */
internal object UpdatePackagePolicy {
    fun validateFile(path: String, directory: File): File {
        val requested = File(path)
        val candidate = requested.canonicalFile
        if (!requested.isAbsolute || requested.absoluteFile != candidate ||
            candidate.parentFile != directory.canonicalFile ||
            candidate.extension.lowercase() != "apk" ||
            !candidate.isFile || !candidate.canRead() || candidate.length() == 0L
        ) {
            throw UpdateFailure("invalid_package", "The update must be a completed APK in the private update cache.")
        }
        return candidate
    }

    fun validateIdentity(
        installedPackage: String,
        candidatePackage: String,
        installedVersion: Long,
        candidateVersion: Long,
        installedSigners: Set<String>,
        candidateSigners: Set<String>,
    ) {
        if (candidatePackage != installedPackage) {
            throw UpdateFailure("package_mismatch", "The downloaded APK belongs to a different application.")
        }
        if (candidateVersion <= installedVersion) {
            throw UpdateFailure("version_not_newer", "The downloaded APK is not newer than this installation.")
        }
        // Deliberately fail closed on missing signers and signing-key rotation. A future
        // rotation needs an explicitly reviewed signing-lineage policy, not a bypass.
        if (installedSigners.isEmpty() || candidateSigners.isEmpty() ||
            candidateSigners != installedSigners
        ) {
            throw UpdateFailure("signature_mismatch", "This APK is not signed with this installation's signing key.")
        }
    }
}
