package api

import (
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
	"github.com/gorilla/mux"
	"github.com/minio/minio-go/v7"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type DownloadManager struct {
	minio *minio.Client
}

func NewDownloadManager(minio *minio.Client) *DownloadManager {
	return &DownloadManager{
		minio: minio,
	}
}

func (d *DownloadManager) DownloadHandler(w http.ResponseWriter, r *http.Request) {
	if d.minio == nil {
		http.Error(w, "Download storage is not configured", http.StatusServiceUnavailable)
		return
	}

	obj := mux.Vars(r)["obj"]
	branch := r.URL.Query().Get("branch")

	if branch != "" {
		p, err := url.PathUnescape(branch)
		if err != nil {
			logger.L().Error("Failed to unescape branch", zap.Error(err))
			http.Error(w, "Invalid branch name", http.StatusBadRequest)
			return
		}

		branch = p
	}

	branch = "stable"

	_, err := d.minio.StatObject(r.Context(), "releases", fmt.Sprintf("%s/%s", branch, obj), minio.StatObjectOptions{})
	if err != nil {
		logger.L().Error("Failed to stat object", zap.Error(err))
		if status.Code(err) == codes.NotFound {
			http.Error(w, "Object not found", http.StatusNotFound)
			return
		}

		http.Error(w, "Failed to access object", http.StatusInternalServerError)
		return
	}

	resp, err := d.minio.PresignedGetObject(r.Context(), "releases", fmt.Sprintf("%s/%s", branch, obj), time.Hour*24, url.Values{})
	if err != nil {
		logger.L().Error(err.Error())

		var respErr minio.ErrorResponse
		if errors.As(err, &respErr) && respErr.StatusCode == http.StatusNotFound {
			http.Error(w, "Object not found", http.StatusNotFound)
			return
		}

		http.Error(w, "Failed to generate download link", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, resp.String(), http.StatusFound)
}
