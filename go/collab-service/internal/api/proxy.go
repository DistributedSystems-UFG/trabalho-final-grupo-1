package api

import (
	"net/http"
	"net/http/httputil"
	"net/url"

	"github.com/gin-gonic/gin"
)

// Proxy returns a handler that reverse-proxies the request to javaBaseURL,
// injecting X-User-ID and X-User-Name headers from the JWT context.
func Proxy(javaBaseURL string) gin.HandlerFunc {
	target, _ := url.Parse(javaBaseURL)

	return func(c *gin.Context) {
		proxy := httputil.NewSingleHostReverseProxy(target)
		proxy.Director = func(req *http.Request) {
			req.URL.Scheme = target.Scheme
			req.URL.Host = target.Host
			req.Host = target.Host
			if userID := c.GetString("userID"); userID != "" {
				req.Header.Set("X-User-ID", userID)
			}
			if userName := c.GetString("userName"); userName != "" {
				req.Header.Set("X-User-Name", userName)
			}
		}
		proxy.ServeHTTP(c.Writer, c.Request)
	}
}
