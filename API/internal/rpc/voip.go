package rpc

import (
	"context"

	"github.com/ArmchairDevelopers/Kyber/API/api/v1/pbapi"
	"github.com/ArmchairDevelopers/Kyber/API/api/v1/pbcommon"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/db"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/models"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/vivox"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type VoipServer struct {
	store    *db.Store
	tokenGen *vivox.VivoxTokenGenerator
	pbapi.UnimplementedVoipServer
}

func NewVoipServer(store *db.Store) *VoipServer {
	tokenGen, err := vivox.NewVivoxTokenGeneratorFromEnv()
	if err != nil {
		logger.L().Warn("Vivox disabled", zap.Error(err))
	}

	return &VoipServer{
		store:    store,
		tokenGen: tokenGen,
	}
}

func (s *VoipServer) Login(ctx context.Context, req *pbcommon.Empty) (*pbapi.VoipLoginResponse, error) {
	if s.tokenGen == nil {
		return nil, status.Error(codes.Unavailable, "Vivox is not configured")
	}

	user := ctx.Value("user").(*models.UserModel)

	username := s.tokenGen.Username(user.Name)
	token := s.tokenGen.Generate("login", s.tokenGen.UserURI(username), nil)
	return &pbapi.VoipLoginResponse{
		Token:       token,
		Username:    username,
		DisplayName: user.Name,
		Issuer:      s.tokenGen.Issuer,
		Domain:      s.tokenGen.Domain,
	}, nil
}

func (s *VoipServer) JoinChannel(ctx context.Context, req *pbapi.VoipJoinChannelRequest) (*pbapi.VoipJoinChannelResponse, error) {
	if s.tokenGen == nil {
		return nil, status.Error(codes.Unavailable, "Vivox is not configured")
	}

	user := ctx.Value("user").(*models.UserModel)

	server, err := s.store.Servers.GetByID(ctx, req.GetServer())
	if err != nil {
		logger.L().Error("Failed to get server by ID", zap.Error(err))
		return nil, status.Error(codes.Internal, "Failed to get server by ID")
	}

	if server == nil {
		return nil, status.Error(codes.Internal, "Server not found")
	}

	username := s.tokenGen.Username(user.Name)
	channelUri := s.tokenGen.PositionalChannelURI(server.ID, 80, 1, 1, 1)
	token := s.tokenGen.Generate("join", s.tokenGen.UserURI(username), &channelUri)

	return &pbapi.VoipJoinChannelResponse{
		Channel:     channelUri,
		AccessToken: token,
	}, nil
}
