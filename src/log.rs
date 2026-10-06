use chrono::prelude::*;

pub fn log_error(scope: &str, message: &str, error: &str) -> () {
    let utc: DateTime<Utc> = Utc::now();
    eprintln!("{utc} [{scope}]: {message} - {error} ");
}
