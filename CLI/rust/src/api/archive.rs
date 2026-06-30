use std::{fs, io};

pub async fn extract(file_path: String, target_dir: String) -> anyhow::Result<()> {
    let fname = std::path::Path::new(&*file_path);
    let file = fs::File::open(fname).unwrap();
    let mut archive = zip::ZipArchive::new(file).unwrap();

    for i in 0..archive.len() {
        let mut file = archive.by_index(i).unwrap();
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

        println!(
            "File {} extracted to \"{}\" ({} bytes)",
            i,
            final_path.display(),
            file.size()
        );
        if let Some(p) = final_path.parent() {
            if !p.exists() {
                fs::create_dir_all(p).unwrap();
            }
        }

        let mut outfile = fs::File::create(&final_path).unwrap();
        io::copy(&mut file, &mut outfile).unwrap();
    }
    return Ok(());
}
