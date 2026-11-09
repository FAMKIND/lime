package com.limemessenger.lime

/** Marks a test that talks to the real staging backend; tools/connected.sh runs these separately, after pushing the test accounts. */
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class Staging
