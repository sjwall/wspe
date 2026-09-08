#[cfg(target_os = "macos")]
use winit::platform::macos::{ActivationPolicy, EventLoopBuilderExtMacOS};

use tray_icon::{
    Icon, TrayIcon, TrayIconBuilder,
    menu::{Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem},
};

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

fn load_icon() -> Icon {
    let svg_data = include_bytes!("../assets/icon-white.svg");
    let opt = resvg::usvg::Options::default();
    let tree = resvg::usvg::Tree::from_data(svg_data, &opt).expect("Failed to parse SVG");

    const WIDTH: u32 = 32;
    const HEIGHT: u32 = 32;

    let mut pixmap =
        resvg::tiny_skia::Pixmap::new(WIDTH, HEIGHT).expect("Failed to create pixmap");

    let size = tree.size();
    let transform = resvg::tiny_skia::Transform::from_scale(
        WIDTH as f32 / size.width(),
        HEIGHT as f32 / size.height(),
    );

    resvg::render(&tree, transform, &mut pixmap.as_mut());

    Icon::from_rgba(pixmap.take(), WIDTH, HEIGHT).expect("Failed to create tray icon")
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

    let mut builder = EventLoop::<AppEvent>::with_user_event();
    #[cfg(target_os = "macos")]
    builder.with_activation_policy(ActivationPolicy::Accessory);
    let event_loop = builder.build().unwrap();

    let proxy = event_loop.create_proxy();
    let hotkey_proxy = proxy.clone();
    let menu_proxy = proxy.clone();

    GlobalHotKeyEvent::set_event_handler(Some(move |event| {
        let _ = hotkey_proxy.send_event(AppEvent::HotKey(event));
    }));

    MenuEvent::set_event_handler(Some(move |event| {
        let _ = menu_proxy.send_event(AppEvent::Menu(event));
    }));

    let mut app = App {
        hotkeys: digits,
        tray_icon: None,
        quit_id: None,
    };

    event_loop.run_app(&mut app).unwrap()
}

#[derive(Debug)]
enum AppEvent {
    HotKey(GlobalHotKeyEvent),
    Menu(MenuEvent),
}

struct App {
    hotkeys: [KeyMap; 10],
    tray_icon: Option<TrayIcon>,
    quit_id: Option<MenuId>,
}

impl ApplicationHandler<AppEvent> for App {
    fn resumed(&mut self, _event_loop: &ActiveEventLoop) {
        if self.tray_icon.is_none() {
            let menu = Menu::new();
            let title_item = MenuItem::new("wspe", false, None);
            let sep = PredefinedMenuItem::separator();
            let quit_item = MenuItem::new("Quit wspe", true, None);

            self.quit_id = Some(quit_item.id().clone());

            let _ = menu.append(&title_item);
            let _ = menu.append(&sep);
            let _ = menu.append(&quit_item);

            let icon = load_icon();

            let tray = TrayIconBuilder::new()
                .with_menu(Box::new(menu))
                .with_tooltip("wspe - Workspace Switcher")
                .with_icon_as_template(true)
                .with_icon(icon)
                .build();

            match tray {
                Ok(t) => self.tray_icon = Some(t),
                Err(e) => eprintln!("Failed to create tray icon: {e}"),
            }
        }
    }

    fn window_event(
        &mut self,
        _event_loop: &ActiveEventLoop,
        _window_id: WindowId,
        _event: WindowEvent,
    ) {
    }

    fn user_event(&mut self, event_loop: &ActiveEventLoop, event: AppEvent) {
        match event {
            AppEvent::HotKey(event) => {
                if event.state == HotKeyState::Released {
                    let hotkeys_iter = self.hotkeys.iter_mut();

                    for val in hotkeys_iter {
                        if val.hotkey.unwrap().id() == event.id {
                            let workspace = val.digit;
                            let result = spaces::switch_space_no_shortcuts(workspace);
                            if result.is_err() {
                                let err = result.err();
                                println!("{err:?}");
                            }
                        }
                    }
                }
            }
            AppEvent::Menu(event) => {
                if let Some(ref quit_id) = self.quit_id {
                    if event.id == *quit_id {
                        event_loop.exit();
                    }
                }
            }
        }
    }
}
