package cache

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const discordAuthKeyPrefix = "discord_auth"

type DiscordAuthCache struct {
	rdb *redis.Client
	ttl time.Duration
}

func NewDiscordAuthCache(rdb *redis.Client, ttl time.Duration) *DiscordAuthCache {
	if ttl <= 0 {
		ttl = defaultTTL
	}
	return &DiscordAuthCache{rdb: rdb, ttl: ttl}
}

func (c *DiscordAuthCache) key(state string) string {
	return fmt.Sprintf("%s:%s", discordAuthKeyPrefix, state)
}

func (c *DiscordAuthCache) Get(ctx context.Context, state string) (*string, error) {
	if c == nil || c.rdb == nil {
		return nil, errors.New("discord auth cache is not configured")
	}

	data, err := c.rdb.Get(ctx, c.key(state)).Bytes()

	if errors.Is(err, redis.Nil) {
		return nil, nil
	}

	if err != nil {
		logger.L().Error("redis GET error", zap.Error(err))
		return nil, err
	}

	token := string(data)

	return &token, nil
}

func (c *DiscordAuthCache) Set(ctx context.Context, state string, token string) error {
	if c == nil || c.rdb == nil {
		return errors.New("discord auth cache is not configured")
	}

	key := c.key(state)

	if err := c.rdb.Set(ctx, key, token, c.ttl).Err(); err != nil {
		logger.L().Error("redis SET error", zap.Error(err))
		return err
	}

	return nil
}
