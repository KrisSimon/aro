plugins {
    id("java")
    id("org.jetbrains.intellij.platform") version "2.10.5"
}

group = "com.krissimon"
version = "1.0.0"

repositories {
    mavenCentral()
    intellijPlatform {
        defaultRepositories()
    }
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

dependencies {
    intellijPlatform {
        intellijIdeaCommunity("2024.1")
        bundledPlugin("org.jetbrains.plugins.textmate")
        pluginVerifier()
        instrumentationTools()
    }
}

intellijPlatform {
    pluginConfiguration {
        name = "ARO Language Support"
        ideaVersion {
            sinceBuild = "241"
            untilBuild = "251.*"
        }
    }

    signing {
        certificateChain = System.getenv("CERTIFICATE_CHAIN") ?: ""
        privateKey = System.getenv("PRIVATE_KEY") ?: ""
        password = System.getenv("PRIVATE_KEY_PASSWORD") ?: ""
    }

    publishing {
        token = System.getenv("PUBLISH_TOKEN") ?: ""
    }
}
