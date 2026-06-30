use crate::api::maxima::RtmPresence;
use crate::frb_generated::{RustAutoOpaque, StreamSink};
use anyhow::bail;
use flutter_rust_bridge::for_generated::futures::SinkExt;
use log::{error, info};
use std::cmp::Ordering;
use std::fs::File;
use std::io::{BufReader, Read, Write};
use std::io::{Cursor, Sink};
use std::path::Path;
use std::sync::atomic::AtomicI32;
use std::sync::{Arc, Mutex};
use std::{fs, io};
use tar::Builder;
use tokio::task;
use zip::write::SimpleFileOptions;
use zip::CompressionMethod;

pub async fn compress(
    file_paths: Vec<String>,
    target_file: String,
    mut progress_stream: StreamSink<(i32, i32)>,
) -> anyhow::Result<()> {
    let target = std::path::Path::new(&target_file);
    let file = File::create(target)?;
    let mut zip = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(CompressionMethod::Stored);

    let mut buffer = Vec::new();
    for (i, file_path) in file_paths.iter().enumerate() {
        info!("Compressing file: {}", file_path);
        let path = std::path::Path::new(&file_path);
        let name = path.file_name().unwrap().to_str().unwrap();

        info!("Adding file: {}", name);
        zip.start_file(name, options)?;
        info!("Reading file: {}", name);
        let mut f = File::open(path)?;
        info!("Writing file: {}", name);
        f.read_to_end(&mut buffer)?;
        zip.write_all(&buffer)?;
        buffer.clear();
        progress_stream
            .add((i as i32, file_paths.len() as i32))
            .unwrap();
    }

    zip.finish()?;

    Ok(())
}

pub async fn compress_tar(
    file_paths: Vec<String>,
    target_file: String,
    mut progress_stream: StreamSink<(i32, i32)>,
) -> anyhow::Result<()> {
    let target = Path::new(&target_file);
    let file = File::create(target)?;
    let mut tar_builder = Builder::new(file);

    for (i, file_path) in file_paths.iter().enumerate() {
        info!("Compressing file: {}", file_path);
        let path = Path::new(file_path);
        let name = path.file_name().unwrap().to_str().unwrap();

        info!("Adding file: {}", name);
        let mut f = File::open(path)?;

        tar_builder.append_file(name, &mut f)?;
        info!("File added: {}", name);

        progress_stream
            .add((i as i32, file_paths.len() as i32))
            .unwrap();
    }

    tar_builder.finish()?;

    Ok(())
}

pub async fn extract_stream(
    file_path: String,
    target_dir: String,
    progress_sink: StreamSink<(i32, i32)>,
) -> anyhow::Result<()> {
    let fname = std::path::Path::new(&file_path);

    // Determine the total number of files in the ZIP archive
    let total_files = {
        let file = File::open(fname)?;
        let archive = zip::ZipArchive::new(file)?;
        archive.len() as i32
    };

    // Generate indices for all files in the archive
    let indices: Vec<usize> = (0..total_files as usize).collect();
    let chunk_size = (indices.len() + 2) / 3; // Round up division
    let chunks: Vec<Vec<usize>> = indices.chunks(chunk_size).map(|c| c.to_vec()).collect();

    // Wrap shared resources in Arc and Mutex for thread safety
    let progress_sink = Arc::new(Mutex::new(progress_sink));
    let target_dir = Arc::new(target_dir);

    // Shared atomic progress counter
    let progress_counter = Arc::new(AtomicI32::new(0));

    // Create tasks to process each chunk
    let mut handles = Vec::new();
    for chunk in chunks {
        let fname = fname.to_path_buf();
        let target_dir = Arc::clone(&target_dir);
        let progress_sink = Arc::clone(&progress_sink);
        let progress_counter = Arc::clone(&progress_counter);

        let handle = task::spawn_blocking(move || {
            // Open a new file handle for each thread
            let file = match File::open(&fname) {
                Ok(f) => f,
                Err(e) => {
                    error!("Failed to open file {:?}: {}", fname, e);
                    return;
                }
            };
            let mut archive = match zip::ZipArchive::new(file) {
                Ok(a) => a,
                Err(e) => {
                    error!("Failed to read ZIP archive: {}", e);
                    return;
                }
            };

            for i in chunk {
                let mut file = match archive.by_index(i) {
                    Ok(f) => f,
                    Err(e) => {
                        error!("Failed to access file at index {}: {}", i, e);
                        continue;
                    }
                };
                let total = total_files;

                if file.is_dir() {
                    let progress =
                        progress_counter.fetch_add(1, core::sync::atomic::Ordering::SeqCst) + 1;
                    progress_sink
                        .lock()
                        .unwrap()
                        .add((progress, total))
                        .unwrap();
                    continue;
                }

                let outpath = match file.enclosed_name() {
                    Some(path) => path.to_owned(),
                    None => {
                        error!("Invalid file path at index {}", i);
                        continue;
                    }
                };
                let final_path = std::path::Path::new(&*target_dir)
                    .join(outpath.file_name().unwrap())
                    .to_owned();

                info!(
                    "File {} extracted to \"{}\" ({} bytes)",
                    i,
                    final_path.display(),
                    file.size()
                );
                if let Some(p) = final_path.parent() {
                    if !p.exists() {
                        if let Err(e) = std::fs::create_dir_all(p) {
                            error!("Failed to create directory {:?}: {}", p, e);
                            continue;
                        }
                    }
                }

                let mut outfile = match File::create(&final_path) {
                    Ok(f) => f,
                    Err(e) => {
                        error!("Failed to create file {:?}: {}", final_path, e);
                        continue;
                    }
                };
                if let Err(e) = io::copy(&mut file, &mut outfile) {
                    error!("Failed to write to file {:?}: {}", final_path, e);
                    continue;
                }

                // Increment the progress counter atomically
                let progress =
                    progress_counter.fetch_add(1, core::sync::atomic::Ordering::SeqCst) + 1;
                progress_sink
                    .lock()
                    .unwrap()
                    .add((progress, total))
                    .unwrap();
            }
        });
        handles.push(handle);
    }

    // Wait for all tasks to complete
    for handle in handles {
        handle.await?;
    }

    Ok(())
}

pub async fn extract(file_path: String, target_dir: String) -> anyhow::Result<()> {
    let fname = std::path::Path::new(&*file_path);
    let file = File::open(fname)?;
    let mut archive = zip::ZipArchive::new(file)?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        if file.is_dir() {
            continue;
        }

        let outpath = match file.enclosed_name() {
            Some(path) => path.to_owned(),
            None => continue,
        };
        let final_path = std::path::Path::new(&*target_dir)
            .join(outpath.file_name().unwrap().to_str().unwrap())
            .to_owned();

        info!(
            "File {} extracted to \"{}\" ({} bytes)",
            i,
            final_path.display(),
            file.size()
        );
        if let Some(p) = final_path.parent() {
            if !p.exists() {
                fs::create_dir_all(p)?;
            }
        }

        let mut outfile = File::create(&final_path)?;
        io::copy(&mut file, &mut outfile)?;
    }

    Ok(())
}
