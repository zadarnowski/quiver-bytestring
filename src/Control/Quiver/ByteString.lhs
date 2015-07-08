> -- | Module:    Control.Quiver.ByteString
> -- Description: Chunked streams of lazy bytestrings
> -- Copyright:   © 2015 Patryk Zadarnowski <pat@jantar.org>
> -- License:     BSD3
> -- Maintainer:  pat@jantar.org
> -- Stability:   experimental
> -- Portability: portable
> --
> -- When binary data is streamed through a Quiver processor, it's often
> -- partitioned arbitrarily into /packets/ with no semantic significance,
> -- beyond facilitation of processing in constant space. This is similar
> -- to the chunking mechanism within lazy bytestrings, and, accordingly,
> -- it's often convenient to unify the two mechanisms, by converting
> -- between processors over lazy bytestrings and processors over strict
> -- chunks of these bytestrings. This module provides efficient
> -- implementations of these conversions.

> module Control.Quiver.ByteString (
>   toChunks, fromChunks
> ) where

> import Data.ByteString (ByteString)
> import Data.Int
> import Control.Quiver

> import qualified Data.ByteString as ByteString
> import qualified Data.ByteString.Lazy as Lazy

> -- | A processors that converts a stream of lazy bytestrings
> --   into a stream of their chunks.

> toChunks :: Functor f => P () Lazy.ByteString ByteString a f [ByteString]
> toChunks = fmap snd (qpure_ Lazy.toChunks () >->> qconcat_)

> -- | A processors that converts a stream of strict bytestring chunks
> --   into a stream of lazy bytestrings with the specified minimum
> --   and maximum size, without copying any data.

> fromChunks :: Functor f => Int64 -> Int64 -> P () ByteString Lazy.ByteString a f [ByteString]
> fromChunks m n
>   | (m > n || n <= 0) = error ("fromChunks: invalid string size range: [" ++ show m ++ ".." ++ show n ++ "]")
>   | (m <= 0) = fromMaxChunks n
>   | (n >= fromIntegral (maxBound::Int)) = fromMinChunks m
>   | (m == n) = fromExactChunks n
>   | otherwise = loop0
>  where
>   loop0 = loop1 m n []
>   loop1 rm rn cs = consume () (loop2 rm rn cs) (deliver (reverse cs))
>   loop2 rm rn cs c = loop3 rm rn cs c (fromIntegral (ByteString.length c))
>   loop3 rm rn cs c cl
>     | (cl <=  0) = loop1 rm rn cs -- skip empty chunks
>     | (cl <  rm) = loop1 (rm - cl) (rn - cl) (c:cs)
>     | (cl <= rn) = let xs = reverse (c:cs)
>                    in produce (Lazy.fromChunks xs) (const loop0) (deliver xs)
>     | otherwise  = let (c1, c2) = ByteString.splitAt (fromIntegral rn) c
>                    in produce (Lazy.fromChunks (reverse (c1:cs))) (const $ loop3 m n [] c2 (cl - rn)) (deliver (reverse (c:cs)))

> fromMaxChunks :: Functor f => Int64 -> P () ByteString Lazy.ByteString a f [ByteString]
> fromMaxChunks n
>   | (n <= 0) = error ("fromChunks: invalid maximum chunk size: " ++ show n)
>   | (n >= fromIntegral (maxBound::Int)) = fmap (const []) (qpure_ Lazy.fromStrict)
>   | otherwise = loop0
>  where
>   loop0 = consume () loop1 (deliver [])
>   loop1 c = loop2 c (fromIntegral (ByteString.length c))
>   loop2 c cl
>     | (cl <= n) = produce (Lazy.fromStrict c) (const loop0) (deliver [c])
>     | otherwise = let (c1, c2) = ByteString.splitAt n' c
>                   in produce (Lazy.fromStrict c1) (const $ loop2 c2 (cl - n)) (deliver [c])
>   n' = fromIntegral n

> fromMinChunks :: Functor f => Int64 -> P () ByteString Lazy.ByteString a f [ByteString]
> fromMinChunks n
>   | (n > 0) = loop0 n []
>   | otherwise = fmap (const []) (qpure_ Lazy.fromStrict)
>  where
>   loop0 r cs = consume () (loop1 r cs) (deliver (reverse cs))
>   loop1 r cs c = loop2 r cs c (fromIntegral (ByteString.length c))
>   loop2 r cs c cl
>     | (cl <= 0) = loop0 r cs -- skip empty chunks
>     | (cl <  r) = loop0 (r - cl) (c:cs)
>     | otherwise = let xs = reverse (c:cs) in produce (Lazy.fromChunks xs) (const $ loop0 n []) (deliver xs)

> fromExactChunks :: Monad m => Int64 -> Pipe ByteString Lazy.ByteString m r
> fromExactChunks n
>   | (n > 0) = loop0 n []
>   | otherwise = error ("Pipes.fromChunks: invalid chunk size: " ++ show n)
>  where
>   loop0 r cs = consume () (loop1 r cs) (deliver (reverse cs))
>   loop1 r cs c = loop2 r cs c (fromIntegral (ByteString.length c))
>   loop2 r cs c cl
>     | (cl <= 0) = loop0 r cs -- skip empty chunks
>     | otherwise = case compare cl r of
>                     LT -> loop0 (r - cl) (c:cs)
>                     EQ -> let xs = reverse (c:cs) in produce (Lazy.fromChunks xs) (const $ loop0 0 []) (deliver xs)
>                     GT -> let (c1, c2) = ByteString.splitAt (fromIntegral r) c
>                           in produce (Lazy.fromChunks (reverse (c1:cs))) (const $ loop2 n [] c2 (cl - r)) (deliver (reverse (c:cs)))
