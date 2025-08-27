package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

func createBigFile(name string) error {
	cmd := fmt.Sprintf("dd if=/dev/urandom of=%s bs=1M count=1000", name)
	return exec.Command("bash", "-c", cmd).Run()
}

func main() {
	ctx := context.Background()

	endpoint := "amygdala-fe02.home.ae-35.com:8000"
	accessKeyID := "0555b35654ad1656d804"
	secretAccessKey := "h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q=="
	useSSL := false

	bucketName := "testnv"
	objectName := "bigfile"

	filePath := "bigfile"

	// Initialize minio client object.
	minioClient, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKeyID, secretAccessKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		log.Fatalln(err)
	}

	log.Printf("%#v\n", minioClient) // minioClient is now set up

	if _, err := os.Stat(filePath); errors.Is(err, os.ErrNotExist) {
		log.Printf("%s does not exist, creating\n", filePath)
		err = createBigFile(filePath)
		if err != nil {
			log.Fatalf("error creating '%s': %v\n", filePath, err)
		}
	}

	// Upload the test file
	// Change the value of filePath if the file is in another location
	contentType := "application/octet-stream"

	// Upload the test file with FPutObject
	info, err := minioClient.FPutObject(ctx, bucketName, objectName, filePath, minio.PutObjectOptions{ContentType: contentType})
	if err != nil {
		log.Fatalln(err)
	}
	log.Printf("Successfully uploaded %s of size %d\n", objectName, info.Size)
}
