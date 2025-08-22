#!/usr/bin/env -S deno run --allow-net --allow-write --allow-read --allow-run

const llamaCppPath = "./llama-cpp";

/**
 * Script to download the latest llama.cpp release for macOS ARM64
 */

async function downloadLatestRelease() {
  console.log("Fetching latest llama.cpp release...");

  // Create temporary directory for download and extraction
  const tempDir = await Deno.makeTempDir({ prefix: "llama-cpp-" });

  // Fetch latest release info from GitHub API
  const response = await fetch(
    "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch releases: ${response.status}`);
  }

  const release = await response.json();
  console.log(`Latest release: ${release.tag_name}`);

  // Find the macOS ARM64 binary asset
  // deno-lint-ignore no-explicit-any
  const macosArm64Asset = release.assets.find((asset: any) =>
    asset.name.endsWith("-macos-arm64.zip")
  );

  if (!macosArm64Asset) {
    throw new Error("Could not find macOS ARM64 asset in the latest release");
  }

  // Download the asset
  console.log(`Downloading ${macosArm64Asset.name}...`);
  const downloadResponse = await fetch(macosArm64Asset.browser_download_url);

  if (!downloadResponse.ok) {
    throw new Error(`Failed to download asset: ${downloadResponse.status}`);
  }

  // Save downloaded zip to temp directory
  const zipPath = `${tempDir}/${macosArm64Asset.name}`;
  const fileData = new Uint8Array(await downloadResponse.arrayBuffer());
  await Deno.writeFile(zipPath, fileData);

  // Extract the zip file
  const extractDir = `${tempDir}/extracted`;
  await Deno.mkdir(extractDir, { recursive: true });

  const unzipOutput = await new Deno.Command("unzip", {
    args: [zipPath, "-d", extractDir],
    stdout: "piped",
    stderr: "piped",
  }).output();

  if (!unzipOutput.success) {
    const stderr = new TextDecoder().decode(unzipOutput.stderr);
    throw new Error(`Extraction failed: ${stderr}`);
  }

  return { tempDir, extractDir, release: release.tag_name };
}

/**
 * Copy only essential llama.cpp files to avoid bloating the app bundle
 */
async function copyWhitelistedFiles(extractDir: string, targetDir: string) {
  // Only include the server binary and required dynamic libraries
  const whitelist = [
    // Main server executable
    "llama-server",      
    // Core llama library
    "libllama.dylib",    
    // Metal Performance Shaders
    "libmtmd.dylib",     
    // Base GGML library
    "libggml-base.dylib", 
    // BLAS acceleration
    "libggml-blas.dylib", 
    // CPU compute
    "libggml-cpu.dylib",  
    // Metal GPU acceleration
    "libggml-metal.dylib", 
    // RPC support
    "libggml-rpc.dylib",  
    // Main GGML library
    "libggml.dylib",     
  ];

  // Copy whitelisted files and make them executable
  for await (const entry of Deno.readDir(extractDir)) {
    if (whitelist.includes(entry.name)) {
      const sourcePath = `${extractDir}/${entry.name}`;
      const targetPath = `${targetDir}/${entry.name}`;

      await Deno.copyFile(sourcePath, targetPath);
      await Deno.chmod(targetPath, 0o755); // Make executable
    }
  }
}

// Main execution
try {
  // Download and extract latest release
  const result = await downloadLatestRelease();
  
  // Ensure target directory exists
  await Deno.mkdir(llamaCppPath, { recursive: true });

  // Remove all existing files (preserve directory to keep Xcode references intact)
  try {
    for await (const entry of Deno.readDir(llamaCppPath)) {
      await Deno.remove(`${llamaCppPath}/${entry.name}`);
    }
  } catch {
    // Directory might not exist, ignore
  }
  
  // Copy essential files to our llama-cpp directory
  await copyWhitelistedFiles(`${result.extractDir}/build/bin`, llamaCppPath);
  
  // Store the version information
  const versionPath = `${llamaCppPath}/version.txt`;
  await Deno.writeTextFile(versionPath, result.release);
  console.log(`Stored version: ${result.release}`);
  
  // Clean up temporary files
  await Deno.remove(result.tempDir, { recursive: true });

  console.log("Update completed successfully!");
} catch (error: unknown) {
  console.error("Error:", error instanceof Error ? error.message : String(error));
  Deno.exit(1);
}
