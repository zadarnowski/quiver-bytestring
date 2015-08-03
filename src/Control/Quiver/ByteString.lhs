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

> {-# LANGUAGE RankNTypes #-}

> module Control.Quiver.ByteString (
>   toChunks, fromChunks, fromChunks',
> ) where

> import Data.ByteString (ByteString)
> import Data.Int
> import Control.Quiver.SP

> import qualified Data.ByteString as ByteString
> import qualified Data.ByteString.Lazy as Lazy

> -- | A processors that converts a stream of lazy bytestrings
> --   into a stream of their chunks.

> toChunks :: Functor f => SP Lazy.ByteString ByteString f ()
> toChunks = sppure Lazy.toChunks >->> spconcat >&> uncurry mappend

> -- | A processors that converts a stream of strict bytestring chunks
> --   into a stream of lazy bytestrings with the specified minimum
> --   and maximum size, without copying any data. If the input does
> --   not provide enough data to complete the final byte string
> --   of the minimum requested length, the stream processor will
> --   fail with the incomplete list of chunks.

> fromChunks :: Functor f => Int64 -> Int64 -> SP ByteString Lazy.ByteString f [ByteString]
> fromChunks m n
>   | (m > n || n <= 0) = error ("fromChunks: invalid string size range: [" ++ show m ++ ".." ++ show n ++ "]")
>   | (m <= 0) = fromMaxChunks n
>   | (n >= fromIntegral (maxBound::Int)) = fromMinChunks m
>   | (m == n) = fromExactChunks n
>   | otherwise = loop0
>  where
>   loop0 = loop1 m n []
>   loop1 rm rn cs = consume () (loop2 rm rn cs) (loope cs)
>   loop2 rm rn cs c = loop3 rm rn cs c (fromIntegral (ByteString.length c))
>   loop3 rm rn cs c cl
>     | (cl <=  0) = loop1 rm rn cs -- skip empty chunks
>     | (cl <  rm) = loop1 (rm - cl) (rn - cl) (c:cs)
>     | (cl <= rn) = Lazy.fromChunks (reverse (c:cs)) >:> loop0
>     | otherwise  = let (c1, c2) = ByteString.splitAt (fromIntegral rn) c in Lazy.fromChunks (reverse (c1:cs)) >:> loop3 m n [] c2 (cl - rn)

> -- | A processors that converts a stream of strict bytestring chunks
> --   into a stream of lazy bytestrings with the specified minimum
> --   and maximum size, without copying any data. This processor
> --   always emits all of its input, so if the input does not provide
> --   enough data to complete the final byte string of the minimum
> --   requested length, the final byte string emitted by the stream
> --   will be shorter than the requested minimum.

> fromChunks' :: Monad f => Int64 -> Int64 -> SP ByteString Lazy.ByteString f e
> fromChunks' m n = fromChunks m n >>! (spemit . Lazy.fromChunks)

> fromMaxChunks :: Functor f => Int64 -> SP ByteString Lazy.ByteString f e
> fromMaxChunks n
>   | (n <= 0) = error ("fromChunks: invalid maximum chunk size: " ++ show n)
>   | (n >= fromIntegral (maxBound::Int)) = sppure Lazy.fromStrict
>   | otherwise = loop0
>  where
>   loop0 = consume () loop1 (deliver SPComplete)
>   loop1 c = loop2 c (fromIntegral (ByteString.length c))
>   loop2 c cl
>     | (cl <= n) = Lazy.fromStrict c >:> loop0
>     | otherwise = let (c1, c2) = ByteString.splitAt n' c in Lazy.fromStrict c1 >:> loop2 c2 (cl - n)
>   n' = fromIntegral n

> fromMinChunks :: Functor f => Int64 -> SP ByteString Lazy.ByteString f [ByteString]
> fromMinChunks n
>   | (n > 0) = loop0 n []
>   | otherwise = sppure Lazy.fromStrict
>  where
>   loop0 r cs = consume () (loop1 r cs) (loope cs)
>   loop1 r cs c = loop2 r cs c (fromIntegral (ByteString.length c))
>   loop2 r cs c cl
>     | (cl <= 0) = loop0 r cs -- skip empty chunks
>     | (cl <  r) = loop0 (r - cl) (c:cs)
>     | otherwise = let xs = reverse (c:cs) in Lazy.fromChunks xs >:> loop0 n []

> fromExactChunks :: Int64 -> SP ByteString Lazy.ByteString f [ByteString]
> fromExactChunks n
>   | (n > 0) = loop0 n []
>   | otherwise = error ("Pipes.fromChunks: invalid chunk size: " ++ show n)
>  where
>   loop0 r cs = consume () (loop1 r cs) (loope cs)
>   loop1 r cs c = loop2 r cs c (fromIntegral (ByteString.length c))
>   loop2 r cs c cl
>     | (cl <= 0) = loop0 r cs -- skip empty chunks
>     | otherwise = case compare cl r of
>                     LT -> loop0 (r - cl) (c:cs)
>                     EQ -> Lazy.fromChunks (reverse (c:cs)) >:> loop0 0 []
>                     GT -> let (c1, c2) = ByteString.splitAt (fromIntegral r) c in Lazy.fromChunks (reverse (c1:cs)) >:> loop2 n [] c2 (cl - r)

> loope cs = deliver (if null cs then SPComplete else SPFailed (reverse cs))
