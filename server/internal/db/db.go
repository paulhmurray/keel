package db

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Connect opens a pgxpool connection using DATABASE_URL and runs migrations.
// migrationsDir is passed in from main so the embed FS lives at package root.
func Connect(ctx context.Context, migrations map[string]string) (*pgxpool.Pool, error) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		return nil, fmt.Errorf("DATABASE_URL is not set")
	}

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("connect pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping db: %w", err)
	}

	if err := runMigrations(ctx, pool, migrations); err != nil {
		pool.Close()
		return nil, fmt.Errorf("run migrations: %w", err)
	}

	return pool, nil
}

func runMigrations(ctx context.Context, pool *pgxpool.Pool, migrations map[string]string) error {
	// Sort migration names to ensure consistent ordering
	names := make([]string, 0, len(migrations))
	for name := range migrations {
		if strings.HasSuffix(name, ".sql") {
			names = append(names, name)
		}
	}
	sort.Strings(names)

	for _, name := range names {
		sql := migrations[name]
		if _, err := pool.Exec(ctx, sql); err != nil {
			return fmt.Errorf("exec migration %s: %w", name, err)
		}
	}
	return nil
}
