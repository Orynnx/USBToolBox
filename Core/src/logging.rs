use log::LevelFilter;

pub fn init() {
    #[cfg(target_os = "android")]
    android_logger::init_once(
        android_logger::Config::default()
            .with_tag("HyperUSBCore")
            .with_max_level(default_level()),
    );

    #[cfg(not(target_os = "android"))]
    init_stderr_logger();
}

fn default_level() -> LevelFilter {
    if cfg!(debug_assertions) {
        LevelFilter::Debug
    } else {
        LevelFilter::Info
    }
}

#[cfg(not(target_os = "android"))]
fn init_stderr_logger() {
    if log::set_logger(&STDERR_LOGGER).is_ok() {
        log::set_max_level(default_level());
    }
}

#[cfg(not(target_os = "android"))]
static STDERR_LOGGER: StderrLogger = StderrLogger;

#[cfg(not(target_os = "android"))]
struct StderrLogger;

#[cfg(not(target_os = "android"))]
impl log::Log for StderrLogger {
    fn enabled(&self, metadata: &log::Metadata<'_>) -> bool {
        metadata.level() <= default_level()
    }

    fn log(&self, record: &log::Record<'_>) {
        if self.enabled(record.metadata()) {
            eprintln!(
                "[{}] {}: {}",
                record.level(),
                record.target(),
                record.args()
            );
        }
    }

    fn flush(&self) {}
}
