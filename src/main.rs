mod spaces;

use global_hotkey::{
    GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState,
    hotkey::{Code, HotKey, Modifiers},
};
use winit::{
    application::ApplicationHandler,
    event::WindowEvent,
    event_loop::{ActiveEventLoop, EventLoop},
    window::WindowId,
};

#[derive(Debug)]
struct KeyMap {
    code: Code,
    digit: u8,
    hotkey: Option<HotKey>,
}

trait KeyMapCallback {
    fn callback(&self);
}

impl KeyMapCallback for KeyMap {
    fn callback(&self) {
        println!("{self:?}");
    }
}

fn main() {
    let hotkeys_manager = GlobalHotKeyManager::new().unwrap();

    let mut digits: [KeyMap; 10] = [
        KeyMap {
            code: Code::Digit0,
            digit: 0,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit1,
            digit: 1,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit2,
            digit: 2,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit3,
            digit: 3,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit4,
            digit: 4,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit5,
            digit: 5,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit6,
            digit: 6,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit7,
            digit: 7,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit8,
            digit: 8,
            hotkey: Option::None,
        },
        KeyMap {
            code: Code::Digit9,
            digit: 9,
            hotkey: Option::None,
        },
    ];

    let digits_iter = digits.iter_mut();

    for val in digits_iter {
        let hotkey = HotKey::new(Some(Modifiers::SUPER), val.code);
        hotkeys_manager.register(hotkey).unwrap();
        val.hotkey = Option::Some(hotkey);
    }

    let event_loop = EventLoop::<AppEvent>::with_user_event().build().unwrap();
    let proxy = event_loop.create_proxy();

    GlobalHotKeyEvent::set_event_handler(Some(move |event| {
        let _ = proxy.send_event(AppEvent::HotKey(event));
    }));

    let mut app = App {
        hotkeys_manager,
        hotkeys: digits,
    };

    event_loop.run_app(&mut app).unwrap()
}

#[derive(Debug)]
enum AppEvent {
    HotKey(GlobalHotKeyEvent),
}

struct App {
    hotkeys_manager: GlobalHotKeyManager,
    hotkeys: [KeyMap; 10],
}

impl ApplicationHandler<AppEvent> for App {
    fn resumed(&mut self, _event_loop: &ActiveEventLoop) {}

    fn window_event(
        &mut self,
        _event_loop: &ActiveEventLoop,
        _window_id: WindowId,
        _event: WindowEvent,
    ) {
    }

    fn user_event(&mut self, _event_loop: &ActiveEventLoop, event: AppEvent) {
        match event {
            AppEvent::HotKey(event) => {
                if event.state == HotKeyState::Released {
                    let hotkeys_iter = self.hotkeys.iter_mut();

                    for val in hotkeys_iter {
                        if val.hotkey.unwrap().id() == event.id {
                            let workspace = val.digit;
                            println!("{workspace:?}");
                            let result = spaces::switch_space_no_shortcuts(workspace);
                            if result.is_err() {
                                let err = result.err();
                                println!("{err:?}");
                            }
                        }
                    }
                }
            }
        }
    }
}
