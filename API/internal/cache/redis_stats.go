package cache

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/models"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const userStatsKeyPrefix = "user_stats"

type StatsCache struct {
	rdb *redis.Client
	ttl time.Duration
}

func NewStatsCache(rdb *redis.Client, ttl time.Duration) *StatsCache {
	if ttl <= 0 {
		ttl = defaultTTL
	}
	return &StatsCache{rdb: rdb, ttl: ttl}
}

func (c *StatsCache) key(userID string, source models.StatsSource) string {
	return fmt.Sprintf("%s:%s:%s", userStatsKeyPrefix, userID, source)
}

func (c *StatsCache) Get(ctx context.Context, userID string, source models.StatsSource) (*models.UserStatsModel, error) {
	if c == nil || c.rdb == nil {
		return nil, nil
	}

	key := c.key(userID, source)
	data, err := c.rdb.Get(ctx, key).Bytes()

	if errors.Is(err, redis.Nil) {
		return nil, nil
	}

	if err != nil {
		logger.L().Error("redis GET error", zap.Error(err))
		return nil, err
	}

	var m models.UserStatsModel
	if err := json.Unmarshal(data, &m); err != nil {
		logger.L().Error("json unmarshal error", zap.Error(err))
		return nil, err
	}

	return &m, nil
}

func (c *StatsCache) Set(ctx context.Context, m *models.UserStatsModel) error {
	if c == nil || c.rdb == nil {
		return nil
	}

	key := c.key(m.UserID, m.Source)
	data, err := json.Marshal(m)
	if err != nil {
		logger.L().Error("json marshal error", zap.Error(err))
		return err
	}
	if err := c.rdb.Set(ctx, key, data, c.ttl).Err(); err != nil {
		logger.L().Error("redis SET error", zap.Error(err))
		return err
	}

	return nil
}

func (c *StatsCache) Delete(ctx context.Context, userID string, source models.StatsSource) error {
	if c == nil || c.rdb == nil {
		return nil
	}

	key := c.key(userID, source)
	if err := c.rdb.Del(ctx, key).Err(); err != nil {
		logger.L().Error("redis DEL error", zap.Error(err))
		return err
	}

	return nil
}
