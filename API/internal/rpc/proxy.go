package rpc

import (
	"context"

	"github.com/ArmchairDevelopers/Kyber/API/api/v1/pbapi"
	"github.com/ArmchairDevelopers/Kyber/API/api/v1/pbcommon"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/util"
	"go.uber.org/zap"
)

type ProxyServer struct {
	proxies *pbapi.ProxyList
	pbapi.UnimplementedProxyServer
}

type yamlProxyInfo struct {
	ID   string `yaml:"id"`
	IP   string `yaml:"ip"`
	Name string `yaml:"name"`
	Flag string `yaml:"flag"`
}

type yamlProxyList struct {
	Proxies []yamlProxyInfo `yaml:"proxies"`
}

func NewProxyServer() *ProxyServer {
	ypl := &yamlProxyList{}

	err := util.LoadConfig("proxies.yaml", ypl)
	if err != nil {
		logger.L().Warn("Proxy list disabled; using an empty proxy list", zap.Error(err))
	}

	pbList := &pbapi.ProxyList{
		Proxies: make([]*pbapi.ProxyInfo, len(ypl.Proxies)),
	}
	for i, p := range ypl.Proxies {
		pbList.Proxies[i] = &pbapi.ProxyInfo{
			Id:   p.ID,
			Ip:   p.IP,
			Name: p.Name,
			Flag: p.Flag,
		}
	}

	return &ProxyServer{
		proxies: pbList,
	}
}

func (s *ProxyServer) GetList(context.Context, *pbcommon.Empty) (*pbapi.ProxyList, error) {
	return s.proxies, nil
}
