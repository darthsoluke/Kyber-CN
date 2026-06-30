use dashmap::DashMap;
use log::warn;
use std::sync::Arc;
use std::sync::Mutex;
use tokio::sync::mpsc::UnboundedSender;
use tokio_tungstenite::tungstenite::Message;

#[derive(Clone)]
pub struct User {
    pub sender: UnboundedSender<Message>,
    pub cancel_token: UnboundedSender<()>,
}

#[derive(Clone)]
pub struct UserManager {
    users: Arc<DashMap<u16, User>>,
    servers: Arc<DashMap<String, User>>,
    user_tokens: Arc<DashMap<String, u16>>,
    next_user_id: Arc<Mutex<u16>>,
}

impl UserManager {
    pub fn new() -> Self {
        UserManager {
            users: Arc::new(DashMap::new()),
            servers: Arc::new(DashMap::new()),
            user_tokens: Arc::new(DashMap::new()),
            next_user_id: Arc::new(Mutex::new(1)),
        }
    }

    // Method to get user by identifier
    pub fn get_user_by_id(&self, id: u16) -> Option<User> {
        self.users.get(&id).map(|x| x.clone())
    }

    // Method to get user by identifier
    pub fn get_server_by_id(&self, id: &str) -> Option<User> {
        self.servers.get(id).map(|x| x.clone())
    }

    pub fn get_user_by_token(&self, token: &str) -> Option<(u16, User)> {
        let user_id = *self.user_tokens.get(token)?;
        self.get_user_by_id(user_id).map(|user| (user_id, user))
    }

    // Method to add or update user
    pub fn add_user(
        &self,
        sender: UnboundedSender<Message>,
        cancel_token: UnboundedSender<()>,
        _server_id: &str,
        token: String,
    ) -> u16 {
        if let Some((existing_id, existing_user)) = self.get_user_by_token(&token) {
            warn!(
                "User token already connected as ID {}, overwriting",
                existing_id
            );
            let _ = existing_user.cancel_token.send(());
            self.remove_user(existing_id);
        }

        let user_id = self.allocate_user_id();
        self.users.insert(
            user_id,
            User {
                sender,
                cancel_token,
            },
        );
        self.user_tokens.insert(token, user_id);
        user_id
    }

    pub fn remove_user(&self, id: u16) {
        self.users.remove(&id);
        if let Some(token_entry) = self
            .user_tokens
            .iter()
            .find(|entry| *entry.value() == id)
            .map(|entry| entry.key().clone())
        {
            self.user_tokens.remove(&token_entry);
        }
    }

    pub fn add_server(
        &self,
        sender: UnboundedSender<Message>,
        cancel_token: UnboundedSender<()>,
        server_id: &str,
    ) {
        let user = User {
            sender,
            cancel_token,
        };
        self.servers.insert(server_id.to_owned(), user);
    }

    pub fn remove_server(&self, id: &str) {
        self.servers.remove(id);
    }

    fn allocate_user_id(&self) -> u16 {
        let mut next_user_id = self
            .next_user_id
            .lock()
            .expect("user id allocator poisoned");
        for _ in 0..u16::MAX {
            let candidate = *next_user_id;
            *next_user_id = next_user_id.wrapping_add(1);
            if *next_user_id == 0 {
                *next_user_id = 1;
            }

            if candidate != 0 && !self.users.contains_key(&candidate) {
                return candidate;
            }
        }

        panic!("proxy user id space exhausted");
    }
}
