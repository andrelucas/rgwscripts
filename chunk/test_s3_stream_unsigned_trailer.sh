#!/bin/bash

export AWS_ACCESS_KEY_ID=0555b35654ad1656d804
export AWS_SECRET_ACCESS_KEY=h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q==

./s3_stream_unsigned_trailer.py --endpoint http://$(hostname -f):8000 testnv us-east-1 obj 100000
