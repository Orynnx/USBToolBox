mod app;
mod info;
mod logging;
mod usb_sub;

fn main() {
    logging::init();

    if let Err(error) = app::run() {
        log::error!("Command failed: {error}");
        eprintln!("hyperusbd: {error}");
        std::process::exit(2);
    }
}
